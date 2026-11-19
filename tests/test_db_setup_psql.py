"""빈 DB 준비 사슬의 psql 단계를 실제 PostgreSQL 에서 돌려 본다.

빈 postgis 컨테이너 하나를 띄우고 db/setup/setup.sh 의 단계를 compose 와 같은 순서로
부른다. 자바·파이썬 이미지 단계(user 부트스트랩·마이그레이션, hub 마이그레이션)는 빌드가
필요해 빼고, hub 마이그레이션 자리에는 hub 소유 역할로 표를 하나 만든다.

역할 SQL 은 형제 레포(../map-project-user·hub·agent)의 것을 쓴다. Docker, 로컬
postgis 이미지, 형제 레포 중 하나라도 없으면 건너뛴다(외부 네트워크를 쓰지 않는다).
컨테이너·네트워크는 maposs-infra-* 이름으로 만들고 끝나면 지운다. 이미지가 데이터 자리를
볼륨으로 선언해 두었으므로 그 자리를 tmpfs 로 덮어 익명 볼륨이 생기지 않게 한다."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT.parent
IMAGE = 'postgis/postgis:17-3.5'
NO_VOLUME = ['--tmpfs', '/var/lib/postgresql/data']
SQL = {
    'user': WORK / 'map-project-user/scripts/sql',
    'hub': WORK / 'map-project-hub/scripts/database-roles.sql',
    'agent': WORK / 'map-project-agent/scripts/database-roles.sql',
}


def _ready():
    if not shutil.which('docker'):
        return 'Docker 가 없다'
    if subprocess.run(['docker', 'image', 'inspect', IMAGE], capture_output=True).returncode != 0:
        return f'로컬에 {IMAGE} 이미지가 없다'
    missing = [str(p) for p in SQL.values() if not p.exists()]
    return f'형제 레포가 없다: {missing}' if missing else None


@unittest.skipIf(_ready(), _ready() or '')
class DatabaseSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tag = uuid.uuid4().hex[:8]
        cls.net = f'maposs-infra-net-{cls.tag}'
        cls.pg = f'maposs-infra-pg-{cls.tag}'
        cls.tmp = tempfile.mkdtemp(prefix='map-project-dbsetup-')
        cls.env = Path(cls.tmp) / '.env'
        cls.state = Path(cls.tmp) / 'state'
        cls.state.mkdir()
        subprocess.run([str(ROOT / 'scripts/make-local-env.sh')], cwd=ROOT, check=True, capture_output=True,
                       env={**os.environ, 'MAP_PROJECT_ENV_FILE': str(cls.env)})
        values = dict(line.split('=', 1) for line in cls.env.read_text().splitlines()
                      if line and not line.startswith('#') and '=' in line)
        cls.values = values
        subprocess.run(['docker', 'network', 'create', cls.net], check=True, capture_output=True)
        subprocess.run(['docker', 'run', '-d', '--rm', '--name', cls.pg, '--network', cls.net,
                        '--network-alias', 'postgres', '--platform', 'linux/amd64',
                        '--tmpfs', '/docker-entrypoint-initdb.d', *NO_VOLUME,
                        '-e', f"POSTGRES_DB={values['MAP_PROJECT_POSTGRES_DB']}",
                        '-e', f"POSTGRES_USER={values['MAP_PROJECT_POSTGRES_USER']}",
                        '-e', 'POSTGRES_PASSWORD',
                        '--entrypoint', 'timeout', IMAGE, '600', 'docker-entrypoint.sh', 'postgres'],
                       check=True, capture_output=True,
                       env={**os.environ, 'POSTGRES_PASSWORD': values['MAP_PROJECT_POSTGRES_PASSWORD']})
        for _ in range(90):
            if subprocess.run(['docker', 'exec', cls.pg, 'pg_isready', '-h', '127.0.0.1', '-U',
                               values['MAP_PROJECT_POSTGRES_USER']], capture_output=True).returncode == 0:
                break
            time.sleep(2)
        else:
            raise RuntimeError('postgres 가 준비되지 않았다')

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['docker', 'rm', '-f', '-v', cls.pg], capture_output=True)
        subprocess.run(['docker', 'network', 'rm', cls.net], capture_output=True)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def step(self, name):
        return subprocess.run(
            ['docker', 'run', '--rm', '--name', f'maposs-infra-setup-{self.tag}', '--network', self.net,
             '--platform', 'linux/amd64', '--env-file', str(self.env), *NO_VOLUME,
             '-v', f'{ROOT}/db/setup:/setup:ro', '-v', f"{SQL['user']}:/sql/user:ro",
             '-v', f"{SQL['hub']}:/sql/hub/database-roles.sql:ro",
             '-v', f"{SQL['agent']}:/sql/agent/database-roles.sql:ro", '-v', f'{self.state}:/state',
             '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
             '--entrypoint', 'timeout', IMAGE, '180', 'bash', '/setup/setup.sh', name],
            capture_output=True, text=True)

    def sql(self, statement):
        result = subprocess.run(['docker', 'exec', self.pg, 'psql', '-X', '-At', '-v', 'ON_ERROR_STOP=1',
                                 '-U', self.values['MAP_PROJECT_POSTGRES_USER'],
                                 '-d', self.values['MAP_PROJECT_POSTGRES_DB'], '-c', statement],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_steps_build_roles_and_the_console_reads_hub_tables(self):
        for name in ('user-prepare', 'platform'):
            result = self.step(name)
            self.assertEqual(result.returncode, 0, f'{name}: {result.stdout[-500:]}{result.stderr[-1500:]}')
        roles = self.sql("SELECT string_agg(rolname, ',' ORDER BY rolname) FROM pg_roles WHERE rolname ~ '^map_'")
        for role in ('map_admin', 'map_hub_owner', 'map_hub_runtime', 'map_agent_runtime', 'map_pg_exporter',
                     'map_user_owner', 'map_user_runtime'):
            self.assertIn(role, roles.split(','))
        # hub 마이그레이션 자리: hub 소유 역할이 표를 만든다. 하나는 이미 있던 볼륨처럼 콘솔 권한을 뺀다.
        self.sql("SET ROLE map_hub_owner; CREATE TABLE hub_data.setup_probe_old (id int);"
                 " CREATE TABLE hub_data.setup_probe (id int)")
        self.sql('REVOKE SELECT ON hub_data.setup_probe_old FROM map_admin')
        result = self.step('finish')
        self.assertEqual(result.returncode, 0, result.stderr[-1500:])
        self.sql('SET ROLE map_hub_owner; CREATE TABLE hub_data.setup_probe_new (id int)')
        for table in ('setup_probe_old', 'setup_probe', 'setup_probe_new'):
            with self.subTest(table=table):
                self.assertEqual(self.sql(f"SELECT has_table_privilege('map_admin', 'hub_data.{table}', 'SELECT')"), 't')
        # 잠시 연 hub 첫 마이그레이션 권한은 거둬졌다.
        self.assertEqual(self.sql("SELECT has_database_privilege('map_hub_owner', current_database(), 'CREATE')"), 'f')
        # 다시 돌려도 안전하다(준비는 건너뛰고 나머지는 같은 결과).
        for name in ('user-prepare', 'platform', 'finish'):
            result = self.step(name)
            self.assertEqual(result.returncode, 0, f'{name} 재실행: {result.stderr[-1500:]}')
        self.assertIn('건너뜀', self.step('user-prepare').stdout)


if __name__ == '__main__':
    unittest.main()
