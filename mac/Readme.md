# macOS `/host_mnt` setup

The remote Kind workflow uses `/host_mnt` so paths passed to Docker Desktop have
the same names in macOS and Docker's Linux VM.

Install the repository configuration on the Mac:

```sh
sudo cp .devcontainer/mac/synthetic.conf /etc/synthetic.conf
sudo chmod 0644 /etc/synthetic.conf
```

Reboot macOS, then verify that the synthetic link points to the filesystem root:

```sh
readlink /host_mnt
# expected output: /
```

The provisioning command performs this check before building or running
anything. If the mapping is missing, it checks whether the SSH user can use
`sudo`, installs this file, and asks for confirmation before rebooting. When a
reboot is approved, it waits for SSH to return and tests the mapping again.

Before rebooting, remote provisioning also checks Docker Desktop's `AutoStart`
setting. Enable **Settings > General > Start Docker Desktop when you sign in**.
Docker Desktop starts after a graphical macOS login, not at the pre-login boot
stage. If automatic login is not configured, make sure the Docker user logs in
after reboot. The script waits up to five minutes for the Docker daemon and
stops with remediation instructions if macOS returns but Docker remains
unavailable.

The remote SSH user must be a Mac administrator when `sudo` requires a password.
When a password is required, it is read directly by remote `sudo` through an SSH
pseudo-terminal with input echo disabled. The provisioning script never reads
the password into a variable, sends it through a pipe, places it in an argument
or environment variable, or writes it to output. System authentication logs may
record the attempted `sudo` command and whether it succeeded, but not the
password.
