# Maintaining Services

## Installing and Enabling a Service

Since all services here only require user-level access, all the services are installed with user-level permissions only.

Create the user-level `systemd` folder:

```shell
mkdir -p ~/.config/systemd/user
```

Run the `install-systemd.sh` script with the service name as the argument.

```shell
./scripts/install-systemd.sh backup-storage
```

This script expects both a `<service-name>.service` and a `<service-name>.timer` file in the `systemd` directory inside this repository. In addition, if the service requires configuration, an example file can be included as `<service-name>.env-example` inside the `systemd` directory.

Both the server and timer units will be sym-linked to `~/.config/systemd/user`.

The script will also take care of running all the necessary commands, like `systemctl --user daemon-reload` and enabling the timer. It will even run some sanity checks on the unit files.

## Useful Service Commands

Services can be run manually by simply specifying the `start` command:

```shell
systemctl --user start backup-storage.service
```

To find out whether the timer was installed correctly, the list of currently active timers can e queried.

```shell
systemctl --user list-timers
```

This list shows which timers are active, but also when the next execution is planned.

User-level services will usually not be executed if the user is not logged in (i.e., the user's last session is closed). This can be circumvented by enabling "linger"

```shell
sudo loginctl enable-linger $USER
```
