# syntax=docker/dockerfile:1



FROM --platform=linux/amd64 python:3.11-slim-bookworm



ARG DEBIAN_FRONTEND=noninteractive
ARG ICEFALL_REF=master
ARG LHOTSE_REF=master



ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    CUDA_MODULE_LOADING=LAZY \
    ICEFALL_HOME=/opt/icefall \
    LHOTSE_HOME=/opt/lhotse \
    PYTHONPATH=/opt/icefall:/opt/lhotse



ENV LD_LIBRARY_PATH=/usr/local/lib/python3.11/site-packages/nvidia/cuda_nvrtc/lib:${LD_LIBRARY_PATH}



SHELL ["/bin/bash", "-o", "pipefail", "-c"]



# 기본 시스템 패키지
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        wget \
        git \
        git-lfs \
        build-essential \
        cmake \
        ninja-build \
        pkg-config \
        ffmpeg \
        sox \
        libsox-fmt-all \
        libsndfile1 \
        libgl1 \
        libglib2.0-0 \
        graphviz \
        vim \
        nano \
        less \
        tmux \
        htop \
        unzip \
        tar \
        gzip \
        libboost-all-dev \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        qt5-qmake \
        qtbase5-dev \
    && rm -rf /var/lib/apt/lists/*



RUN python -m pip install --upgrade \
    pip \
    setuptools \
    wheel \
    packaging

# Kenlm 
RUN git clone --depth 1 https://github.com/kpu/kenlm.git /opt/kenlm \
    && mkdir -p /opt/kenlm/build \
    && cd /opt/kenlm/build \
    && cmake .. \
    && cmake --build . -j"$(nproc)"  

ENV PATH=/opt/kenlm/build/bin:${PATH}

# PyTorch 2.4.0 + CUDA 12.1
RUN python -m pip install \
    torch==2.4.0 \
    torchaudio==2.4.0 \
    --index-url https://download.pytorch.org/whl/cu121



# k2: CUDA 12.1 / Torch 2.4.0 / Python 3.11
RUN python -m pip install \
    --no-deps \
    --only-binary=:all: \
    "k2==1.24.4.dev20240725+cuda12.1.torch2.4.0" \
    -f https://k2-fsa.github.io/k2/cuda.html



# kaldifeat: CUDA 12.1 / Torch 2.4.0 / Python 3.11
RUN python -m pip install \
    --no-deps \
    --only-binary=:all: \
    "kaldifeat==1.25.4.dev20240725+cuda12.1.torch2.4.0" \
    -f https://csukuangfj.github.io/kaldifeat/cuda.html



# Lhotse
RUN git clone \
        --depth 1 \
        --branch "${LHOTSE_REF}" \
        https://github.com/lhotse-speech/lhotse.git \
        /opt/lhotse \
    && python -m pip install /opt/lhotse



# Icefall
RUN git clone \
        --depth 1 \
        --branch "${ICEFALL_REF}" \
        https://github.com/k2-fsa/icefall.git \
        /opt/icefall



# Icefall requirements에서 이미 버전을 고정한 패키지는 제외
RUN python - <<'PY'
from pathlib import Path
import re



source = Path("/opt/icefall/requirements.txt")
target = Path("/tmp/icefall-requirements.txt")



excluded = re.compile(
    r"^\s*(torch|torchaudio|torchvision|k2|kaldifeat|lhotse)"
    r"([<>=!~\s]|$)",
    re.IGNORECASE,
)



lines = []
if source.exists():
    for line in source.read_text().splitlines():
        if not excluded.match(line):
            lines.append(line)



target.write_text("\n".join(lines) + "\n")
PY



RUN python -m pip install \
    -r /tmp/icefall-requirements.txt



RUN python -m pip install lilcom



# 학습 시 자주 사용하는 보조 패키지
RUN python -m pip install \
    graphviz \
    tensorboard \
    sentencepiece \
    soundfile \
    scipy \
    pandas \
    pyyaml \
    tqdm \
    psutil \
    rich \
    librosa \
    torchinfo \
    pydub \
    "numpy>=2.0.0" \
    "transformers==4.36.2" \
    "kiwipiepy==0.23.0" \
    "kiwipiepy_model==0.23.0" \
    "safetensors==0.7.0" 



RUN python -m pip install "pyctcdecode==0.5.0"

COPY spacing /opt/spacing

COPY language /opt/language

COPY speech.dev /opt/speech.dev

COPY src /opt/src
 
# GPU가 없는 빌드 머신에서도 가능한 설치 검증
# k2와 kaldifeat는 실제 import하지 않고 버전 메타데이터만 확인
RUN python - <<'PY'
from importlib.metadata import version
from pathlib import Path



print("Python:", version("pip"))
print("Torch:", version("torch"))
print("TorchAudio:", version("torchaudio"))
print("k2:", version("k2"))
print("kaldifeat:", version("kaldifeat"))
print("Lhotse:", version("lhotse"))



assert Path("/opt/icefall/icefall/__init__.py").exists()
print("Icefall source: OK")
print("Build validation: OK")
PY


RUN python -m pip install --upgrade "numpy==1.26.4"



WORKDIR /workspace



# 학습 자동 실행 없음
CMD ["/bin/bash"]
