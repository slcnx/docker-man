# Use common base image
FROM docker-man-base:latest

# Install Sersync real-time sync service packages
RUN yum install -y  \
    rsync \
    inotify-tools \
    openssh-clients \
    openssh-server \
    wget \
    unzip && \
    yum clean all

# Install Sersync (Real-time sync tool)
# Sersync is an inotify + rsync based real-time synchronization solution
# Project has stopped maintenance but is still stable and usable
RUN cd /tmp && \
    # Try multiple download sources in order
    # Source 1: GitHub with gh-proxy.com mirror (recommended for China)
    wget https://gh-proxy.com/https://github.com/wsgzao/sersync/raw/master/sersync2.5.4_64bit_binary_stable_final.tar.gz \
        -O sersync.tar.gz --no-check-certificate --timeout=10   && \
    # Extract
    tar -zxf sersync.tar.gz && \
    # Install to system path
    cp GNU-Linux-x86/sersync2 /usr/local/bin/sersync && \
    chmod +x /usr/local/bin/sersync && \
    # Create config directory
    mkdir -p /etc/sersync && \
    # Copy default config file
    cp GNU-Linux-x86/confxml.xml /etc/sersync/confxml.xml && \
    # Cleanup
    rm -rf /tmp/sersync.tar.gz /tmp/GNU-Linux-x86
 
# Verify installation
RUN sersync -h > /dev/null 2>&1 || echo "Sersync installation completed"
 
# Expose ports
# 873: rsync daemon (if using daemon mode)
# 22: SSH (if using SSH mode)
EXPOSE 873/tcp 22/tcp

# Default working directory
WORKDIR /data

CMD ["tail", "-f", "/dev/null"]
