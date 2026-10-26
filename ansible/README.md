# elm-pebble host

Ansible for a Debian 13 server. It creates a `deploy` user, issues an OpenSSH user certificate, disables root and password login only after that certificate works, then runs the IDE, Postgres 18, Caddy, and a daily database dump.

Run it from this directory so `ansible.cfg` is picked up:

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
cp secrets.yml.example secrets.yml
# Put the server IP in inventory/hosts.yml.
# Put the ACME email and SMTP settings in secrets.yml.
ansible-playbook site.yml
```

The first run logs in as root with the provider password. `IdentitiesOnly` and `PubkeyAuthentication=no` keep the 1Password agent from offering every key before the password. Run `ansible-playbook site.yml --ask-pass`. Do not write the password into the inventory. When it finishes, root SSH is off. Set `ansible_user` to `deploy`, point `ansible_ssh_private_key_file` at `keys/deploy`, and replace `ansible_ssh_common_args` with `-o IdentitiesOnly=yes -o IdentityAgent=none -o CertificateFile=keys/deploy-cert.pub`.

The user CA private key stays in `keys/` on this machine. The server only gets `keys/user_ca.pub`. Ansible logs in with `keys/deploy` and `keys/deploy-cert.pub`. That key has no passphrase, so the certificate check can run non-interactively. Your own key is also signed (`id_ed25519-cert.pub`); it has a passphrase, so use it with `IdentityAgent=none` and the certificate file. Add a host entry so the 1Password agent does not skip the certificate:

```
Host elm-pebble
  HostName SERVER_IP
  User deploy
  IdentityFile ~/projects/elm-pebble/ansible/keys/deploy
  CertificateFile ~/projects/elm-pebble/ansible/keys/deploy-cert.pub
  IdentityAgent none
  IdentitiesOnly yes
```

`secrets.yml`, `inventory/hosts.yml`, and `keys/` are gitignored. A `secret_key_base` or `ide_email_hash_pepper` in `secrets.yml` is copied into `/etc/elm-pebble/env`. Otherwise those two are generated once on the server and reused. The database password is always generated there. `phx_host` is the public name Caddy serves. An empty `acme_email` uses `ide_mail_from`.

The playbook deploys `git archive HEAD`. Commit the tree you want on the server before running it.

Point `ide.elm-pebble.dev` at the new server yourself. Caddy requests the certificate once port 80 reaches the host. Postgres listens only on the Docker network. The daily dump is `/var/backups/elm-pebble/` on this same disk, kept for 7 days.
