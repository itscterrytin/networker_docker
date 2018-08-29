# docker-networker

EMC networker server instance for Testing.

- Bootstraps an EMC networker server, typically from a remote disk or clone device.
- Facilitates automated recovery tests by providing a generic interface for recovery requests:
  - no client passwords or client certificates
  - a simple unix socket interface which abstracts away the recovery command syntax.

The container is built from a standard Centos base image, hence building and
running the container simulates a Bare Metal Restore scenario.

Given
- a backup device containing regular backups and one or more bootstrap backups, accessible from within a docker container.
- the corresponding device configuration file (used by nsradmin to import the device configuration)
- a bootstrap ID and volume name (standard networker bootstrap information)

running this container will:
- configure the device in networker
- recover a subset of the server resources needed for the recovery tests
- recover the client resources from the bootstrap
- restore the client indexes
- starts listening on a socket for recovery requests

After an initial run, the container can be stopped and started as needed, while
keeping the media database.

## Usage

### Start the networker server container

The device configuration file is mounted under /bootstrapdevice.
The volume where the results of the recovery requests will be stored is mounted under /recovery_area.
In the default setup, this volume will also contain the listening socket.
The hostname of the container MUST be the same as the hostname of the original networker server.
```bash
docker run -d \
--name networker-test-dr \
-h backupserver.example.com \
-v /root/clone_device:/bootstrapdevice \
-v /root/workspace:/recovery_area \
-p 192.168.107.60:9000-9001:9000-9001 \
-p 192.168.107.60:7937-7946:7937-7946 \
docker-networker:latest \
4251920743,bootstrapdisk1
```

### Recover a file on the host where the container is running

```bash
$ echo '{ "client": "client1.example.com", "path": "/data/backup_file" }' \
  | socat -,ignoreeof /workspace/networker.socket
07/31 16:37:47: starting recovery client.example.net /data/backup_label
Recovering 1 file from /data/backup_label into /recovery_area/client1.example.com
Requesting 1 file(s), this may take a while...
Recover start time: Mon Jul 23 17:13:52 2018
Received 1 file(s) from NSR server 'backupserver.example.com'
Recover completion time: Mon Jul 23 17:13:53 2018

$ ls -l /workspace/client1.example.net/
total 4
-rw------- 1 107 110 210 Jul 30 23:00 backup_file

```

### Recover a file in a container that runs extra checks

Mounting /workspace/client1.example.com and the socket in a container allows to recover and validate files from within the container.

```bash
docker run --name "networker-test-recover" -h client1.example.com -v /root/workspace/client1.example.com:/recovery_area -v /root/workspace/networker.socket:/recovery_socket docker-networker:latest

```

There are security implications. It is degined to run on a secured host.


### Thanks https://github.com/viaacode/docker-networker-rt where Most info was referred from