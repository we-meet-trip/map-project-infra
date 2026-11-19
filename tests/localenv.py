"""시험이 compose 를 렌더할 때 쓰는 환경파일. 빠른 시작과 같은 생성기로 만든다.

본보기(.env.example)는 비밀값 자리가 비어 있어 그대로는 필수 값 검사에 걸린다.
생성기가 만든 파일로 렌더하면 생성기와 compose 가 서로 맞는지도 함께 본다."""
import atexit
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
_path = None


def generated_env():
    global _path
    if _path is None:
        directory = tempfile.mkdtemp(prefix='map-project-env-')
        atexit.register(shutil.rmtree, directory, True)
        target = Path(directory) / '.env'
        subprocess.run([str(ROOT / 'scripts/make-local-env.sh')], cwd=ROOT, check=True,
                       capture_output=True, env={**os.environ, 'MAP_PROJECT_ENV_FILE': str(target)})
        _path = str(target)
    return _path
