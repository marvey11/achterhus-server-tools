# Maintaining Services

## Installing and Enabling a Service

Since all services here only require user-level access, all the services are installed with user-level permissions only.

Create the user-level `systemd` folder:

```shell
mkdir -p ~/.config/systemd/user
```

Symlink all the service and timer files into that newly created directory.

```shell
ln -s ~/achterhus-nas-tools/services/backup-drives.service ~/.config/systemd/user/backup-drives.service
ln -s ~/achterhus-nas-tools/services/backup-drives.timer ~/.config/systemd/user/backup-drives.timer
```

Subsequently, the daemon needs to be reloaded. This ensures that all services are reloaded as well.

```shell
systemctl --user daemon-reload
```

This also applied if any of the service or timer files has been modified.

Services can be run manually b simply specifying the `start` command:

```shell
systemctl --user start backup-drives.service
```

Timers need to be enabled separately.

```shell
systemctl --user enable --now backup-drives.timer
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
