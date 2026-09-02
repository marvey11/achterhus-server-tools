# To-do List

- [x] Sanitise the JSON configuration with regards to paths
- [ ] Sanitise the timestamps on the frontend (UTC vs. local time)
- [x] Add the database backup script and `systemd` units
- [ ] Change the project to one fully managed by `uv`
  - [ ] Put the executable `bash` scripts in `bin`
  - [ ] Add the Python code under `src` in separate packages (including `core` for common code)
- [ ] Create a shared library which bundles service-level functionality, like querying its shared directory
- [ ] Add metadata extraction to `get-audiothek-podcasts.py`
