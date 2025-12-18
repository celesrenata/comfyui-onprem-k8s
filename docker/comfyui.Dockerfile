# ---------- Base ----------
FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Los_Angeles \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PYTHON=python3.12 \
    COMFYUI_PATH=/home/workspace/ComfyUI \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /home/workspace

# ---------- System deps ----------
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates \
       git \
       curl \
       wget \
       ffmpeg \
       python3.12-full \
       python3.12-dev \
       python3.12-venv \
       python3-git \
       libgl1 \
       libglib2.0-0 \
       build-essential \
       cmake \
  && rm -rf /var/lib/apt/lists/*

# ---------- Python venv ----------
RUN python3.12 -m venv /opt/venv-template \
 && . /opt/venv-template/bin/activate \
 && pip install -U pip setuptools wheel \
 && pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130 \
 && pip install \
    diffusers>=0.31.0 \
    bitsandbytes \
    triton \
    llama-cpp-python \
    deepdiff \
    insightface \
    pillow-avif-plugin \
    jxlpy \
    pytorch-msssim
    
# ---------- ComfyUI ----------
ARG COMFYUI_VERSION=fc657f4
ARG COMFYUI_MANAGER_VERSION=bba55d4

RUN git clone https://github.com/comfyanonymous/ComfyUI.git $COMFYUI_PATH \
    && cd $COMFYUI_PATH && git checkout ${COMFYUI_VERSION} \
    && git clone https://github.com/Comfy-Org/ComfyUI-Manager.git $COMFYUI_PATH/custom_nodes/ComfyUI-Manager \
    && cd $COMFYUI_PATH/custom_nodes/ComfyUI-Manager && git checkout ${COMFYUI_MANAGER_VERSION}

RUN . /opt/venv-template/bin/activate && pip install -r $COMFYUI_PATH/requirements.txt

# ---------- Templates ----------
RUN mkdir -p /opt/templates/custom_nodes /opt/templates/user/default \
    && cp -r $COMFYUI_PATH/custom_nodes/* /opt/templates/custom_nodes/

# ---------- Init script ----------
COPY <<'EOF' /opt/init-nfs-shares.sh
#!/bin/bash
set -e
echo "Checking NFS shares..."

if [ ! -f "/opt/venv/pyvenv.cfg" ]; then
    echo "Initializing venv..."
    rm -rf /opt/venv/* 2>/dev/null || true
    cp -r /opt/venv-template/* /opt/venv/
fi

[ ! "$(ls -A /home/workspace/ComfyUI/custom_nodes 2>/dev/null)" ] && \
    cp -r /opt/templates/custom_nodes/* /home/workspace/ComfyUI/custom_nodes/

[ ! "$(ls -A /home/workspace/ComfyUI/user 2>/dev/null)" ] && \
    cp -r /opt/templates/user/* /home/workspace/ComfyUI/user/

echo "Initialization complete"
EOF

# ---------- Start script ----------
COPY <<'EOF' /opt/start-comfyui.sh
#!/bin/bash
set -e
/opt/init-nfs-shares.sh
export VIRTUAL_ENV=/opt/venv PATH="/opt/venv/bin:${PATH}"
cd $COMFYUI_PATH
exec $PYTHON main.py --listen 0.0.0.0 --port 50000
EOF

RUN chmod +x /opt/init-nfs-shares.sh /opt/start-comfyui.sh

# ---------- User ----------
RUN chown -R 1000:1000 /home/workspace /opt/venv-template /opt/templates

USER ubuntu
ENV PATH="$COMFYUI_PATH:$PATH"
EXPOSE 50000

CMD ["/opt/start-comfyui.sh"]
