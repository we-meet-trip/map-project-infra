"""Exercise real Compose interpolation without exposing any environment values."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest
from localenv import generated_env

ROOT = Path(__file__).resolve().parent.parent

@unittest.skipUnless(shutil.which('docker'), 'Docker Compose is required')
class ServiceEnvironmentTests(unittest.TestCase):
    def test_secret_access_is_limited_to_its_consumers(self):
        result = subprocess.run(['docker','compose','--env-file',generated_env(),'-f','docker-compose.yml',
                                 '--profile','full','--profile','vision','config','--format','json'],
                                cwd=ROOT, capture_output=True, text=True,
                                env={**os.environ,'USER_JWT_PRIVATE_KEY':'sentinel-signing-key',
                                     'MAP_PROJECT_POSTGRES_PASSWORD':'sentinel-database-password',
                                     'UNRELATED_SECRET':'must-not-be-forwarded'})
        self.assertEqual(result.returncode, 0, 'Compose must render')
        services=json.loads(result.stdout)['services']
        for name in ('agent','hub','yolo'):
            self.assertNotIn('USER_JWT_PRIVATE_KEY', services[name]['environment'])
        for name in ('user','hub','yolo'):
            self.assertNotIn('MAP_PROJECT_POSTGRES_PASSWORD', services[name]['environment'])
        for name in ('user','agent','hub','yolo'):
            self.assertNotIn('UNRELATED_SECRET', services[name]['environment'])
            self.assertNotIn('env_file', services[name])
        self.assertIn('MAP_PROJECT_HUB_ADMIN_INTERNAL_TOKEN', services['hub']['environment'])
        for name in ('user', 'agent', 'yolo'):
            self.assertNotIn('MAP_PROJECT_HUB_ADMIN_INTERNAL_TOKEN', services[name]['environment'])
        self.assertNotIn('MAP_PROJECT_POSTGRES_USER',services['user']['environment'])
        self.assertFalse(any(k.startswith('USER_MIGRATION_') for k in services['user']['environment']))
        self.assertEqual(services['user']['environment']['USER_DATABASE_USER'],'map_user_runtime')
        self.assertEqual(services['user']['environment']['USER_JWT_PRIVATE_KEY'],'sentinel-signing-key')
        self.assertEqual(services['agent']['environment']['MAP_PROJECT_TRAINING_CAPTURE_ENABLED'],'false')
        # The database container's operator password must not reach a service
        # merely because both read a variable of the same name.
        self.assertNotEqual(services['agent']['environment']['AGENT_DATABASE_PASSWORD'],
                            'sentinel-database-password')
        self.assertEqual(services['agent']['environment']['AGENT_DATABASE_USER'],'map_agent_runtime')
        self.assertNotIn('AGENT_CHECKPOINT_MIGRATION_DSN',services['agent']['environment'])
        self.assertNotIn('HUB_MIGRATION_DATABASE_URL',services['hub']['environment'])
        self.assertIn('map_hub_runtime',services['hub']['environment']['HUB_DATABASE_URL'])


@unittest.skipUnless(shutil.which('docker'), 'Docker Compose is required')
class EmptyValueTests(unittest.TestCase):
    """본보기의 빈 줄은 compose 를 거쳐 빈 문자열로 들어간다. 문자열 설정에는 '설정 안 됨'
    이지만 불리언·숫자 설정에는 파싱 오류라 서비스가 부팅하지 못한다."""
    STRING_LIKE = re.compile(r'(KEY|KEYS|SECRET|TOKEN|ID|PASSWORD|URL|URI|PATH|CONTACT|DSN)(_FALLBACK)?$')

    def test_only_string_settings_reach_services_empty(self):
        for compose in ('docker-compose.yml', 'docker-compose.admin.yml'):
            result = subprocess.run(['docker', 'compose', '--env-file', generated_env(), '-f', compose,
                                     '--profile', '*', 'config', '--format', 'json'],
                                    cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, 'Compose must render')
            for name, service in json.loads(result.stdout)['services'].items():
                for key, value in (service.get('environment') or {}).items():
                    if value == '':
                        with self.subTest(compose=compose, service=name, key=key):
                            self.assertRegex(key, self.STRING_LIKE)


class TestStackOriginTests(unittest.TestCase):
    def test_test_stack_allows_the_hosting_origin_that_e2e_checks(self):
        # The generated test environment and the cross-origin check must name the same
        # hosting origin; a placeholder here blocks the hosted web app with 403.
        generated = re.search(r'^set_kv USER_CORS_ALLOWED_ORIGINS "([^"]+)"$',
                              (ROOT / 'scripts/make-test-env.sh').read_text(), re.M)
        checked = re.search(r'^WEB_ORIGIN="\$\{E2E_WEB_ORIGIN:-([^}]+)\}"$',
                            (ROOT / 'scripts/e2e.sh').read_text(), re.M)
        self.assertIsNotNone(generated)
        self.assertIsNotNone(checked)
        self.assertEqual(generated[1], checked[1])
