FROM ubuntu:18.04

# Update OS
RUN apt update
RUN apt dist-upgrade --purge -y

# Install OS dependencies
RUN apt install -y \
    ffmpeg \
    sox \
    libgmp-dev \
    libavutil-dev \
    libavformat-dev \
    libavcodec-dev \
    libswscale-dev \
    libavdevice-dev \
    libgirepository1.0-dev \
    libgtk-3-dev \
    libpango1.0-dev \
    libgdk-pixbuf2.0-dev \
    libgstreamer1.0-dev \
    gstreamer1.0-libav \
    gstreamer1.0-gtk3 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad
RUN curl -sSL https://get.haskellstack.org/ | sh
RUN apt install -y git
RUN apt clean

# Set up directory
RUN mkdir -p /app
WORKDIR /app

# Cache stack until stack.yml changes
COPY stack.yaml /app/
RUN stack setup

# Cache build dependencies until *.cabal change
COPY *.cabal /app/
RUN stack build --only-dependencies

# Build
COPY . /app/
RUN stack install

# Default command
CMD /root/.local/bin/komposition

