# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

# Debian Jessie debootstrap from 2017-02-27
# https://github.com/docker-library/official-images/commit/aa5973d0c918c70c035ec0746b8acaec3a4d7777
FROM debian@sha256:52af198afd8c264f1035206ca66a5c48e602afb32dc912ebf9e9478134601ec4

MAINTAINER idekernel Project

USER root

#copy everything
RUN mkdir -p /srv/kernel
COPY . /srv/kernel

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN REPO=http://cdn-fastly.deb.debian.org \
 && echo "deb $REPO/debian jessie main\ndeb $REPO/debian-security jessie/updates main" > /etc/apt/sources.list \
 && apt-get update && apt-get -yq dist-upgrade \
 && apt-get install -yq --no-install-recommends \
    libav-tools \
    wget \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    git \
    vim \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Install Tini
RUN wget --quiet https://github.com/krallin/tini/releases/download/v0.10.0/tini && \
    echo "1361527f39190a7338a0b434bd8c88ff7233ce7b9a4876f3315c22fce7eca1b0 *tini" | sha256sum -c - && \
    mv tini /usr/local/bin/tini && \
    chmod +x /usr/local/bin/tini

# Configure environment
ENV CONDA_DIR /opt/conda
ENV PATH $CONDA_DIR/bin:$PATH
ENV SHELL /bin/bash
ENV NB_USER jovyan
ENV NB_UID 1000
ENV HOME /home/$NB_USER
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV NODE_VERSION 7.7.4

# Create jovyan user with UID=1000 and in the 'users' group
RUN useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER $CONDA_DIR

USER $NB_USER

# Setup jovyan home directory
RUN mkdir /home/$NB_USER/work && \
    mkdir /home/$NB_USER/.jupyter && \
    echo "cacert=/etc/ssl/certs/ca-certificates.crt" > /home/$NB_USER/.curlrc

# Install conda as jovyan
RUN cd /tmp && \
    mkdir -p $CONDA_DIR && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-4.2.12-Linux-x86_64.sh && \
    echo "c59b3dd3cad550ac7596e0d599b91e75d88826db132e4146030ef471bb434e9a *Miniconda3-4.2.12-Linux-x86_64.sh" | sha256sum -c - && \
    /bin/bash Miniconda3-4.2.12-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Miniconda3-4.2.12-Linux-x86_64.sh && \
    $CONDA_DIR/bin/conda config --system --add channels conda-forge && \
    $CONDA_DIR/bin/conda config --system --set auto_update_conda false && \
    conda clean -tipsy
    
USER root
WORKDIR /home/$NB_USER/work
#install nodejs
RUN wget --quiet "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" \
  && tar -xJf "node-v$NODE_VERSION-linux-x64.tar.xz" -C /usr/local --strip-components=1 \
  && rm "node-v$NODE_VERSION-linux-x64.tar.xz"
  
# RUN cd /home/$NB_USER/work
# RUN git clone https://github.com/nodejs/node.git
# RUN cd ./node
# RUN ls -l
# RUN ./configure
# RUN make
# RUN make install
#RUN wget --quiet https://nodejs.org/dist/v6.10.1/node-v6.10.1-linux-x64.tar.xz
#RUN xz -d node-v6.10.1-linux-x64.tar.xz
#RUN tar -xvf node-v6.10.1-linux-x64.tar
#RUN ln -s /home/$NB_USER/work/node-v6.10.1-linux-x64/bin/npm /usr/local/bin/npm
#RUN ln -s /home/$NB_USER/work/node-v6.10.1-linux-x64/bin/node /usr/local/bin/node
#install npm
# RUN cd /home/$NB_USER/work
# RUN wget https://npmjs.org/install.sh --no-check-certificate
# RUN chmod 777 install.sh
# RUN ./install.sh
# Install Jupyter notebook client ipykernel kernelgateway
# update pip setuptools
RUN conda update pip setuptools

#install notebook
RUN cd /srv/kernel/notebook \
  && npm install \
  && pip install -e .
#install client
RUN cd /srv/kernel/jupyter_client \
  && npm install \
  && pip install -e .
#install ipykernel
RUN cd /srv/kernel/ipykernel \
  && npm install \
  && pip install -e .
  
EXPOSE 8888


# Configure container startup
ENTRYPOINT ["tini", "--"]
CMD ["jupyter", "kernelgateway", "--KernelGatewayApp.ip=0.0.0.0", "--KernelGatewayApp.port=8888"]

# Add local files as late as possible to avoid cache busting
COPY start.sh /usr/local/bin/
COPY start-notebook.sh /usr/local/bin/
COPY jupyter_notebook_config.py /home/$NB_USER/.jupyter/
RUN chown -R $NB_USER:users /home/$NB_USER/.jupyter
RUN chown -R $NB_USER:users /home/$NB_USER/.local



USER root

# Install Python 2 packages
# Remove pyqt and qt pulled in for matplotlib since we're only ever going to
# use notebook-friendly backends in these images
RUN conda create --quiet --yes -p $CONDA_DIR/envs/python2 python=2.7 \
    ipykernel

# Add shortcuts to distinguish pip for python2 and python3 envs
RUN ln -s $CONDA_DIR/envs/python2/bin/pip $CONDA_DIR/bin/pip2

# Install Python 2 kernel spec globally to avoid permission problems when NB_UID
# switching at runtime and to allow the notebook server running out of the root
# environment to find it. Also, activate the python2 environment upon kernel
# launch.
RUN pip install kernda --no-cache && \
    $CONDA_DIR/envs/python2/bin/python -m ipykernel install && \
    kernda -o -y /usr/local/share/jupyter/kernels/python2/kernel.json && \
    pip uninstall kernda -y
    
# Switch back to jovyan to avoid accidental container runs as root
WORKDIR /home/$NB_USER    

USER $NB_USER
