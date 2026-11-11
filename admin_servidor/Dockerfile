FROM ubuntu:24.04

# Herramientas que necesita el script (cliente de MySQL, rsync, SSH, red)
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo mysql-client rsync openssh-client iproute2 iputils-ping procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# El script se niega a correr como root: se crea un usuario normal (UID 1000, igual que fc en la VM)
RUN (id ubuntu >/dev/null 2>&1 && userdel -r ubuntu || true) \
    && useradd -m -u 1000 -s /bin/bash fc \
    && echo 'fc ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/fc \
    && chmod 440 /etc/sudoers.d/fc

ENV USER=fc HOME=/home/fc

# Se copia el script y se le da permiso de ejecución
COPY --chown=fc:fc . /home/fc/admin_servidor
USER fc
WORKDIR /home/fc/admin_servidor
RUN chmod +x admin_servidor.sh modulos/*.sh

ENTRYPOINT ["./admin_servidor.sh"]
