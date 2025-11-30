TOOLS for Autocurriculum
=========================

This folder contains diagnostic and corrective CLI scripts used during the
site cleanup to remove stale 'ollama' AI provider entries and to register
missing capabilities for `contentbank/contenttype/file`.

Files:
- `remove_ollama_config_plugins.php` - backup and optionally delete `config_plugins` rows matching 'ollama'.
- `check_leftover_ollama.php` - scans DB & local plugin dir names for 'ollama' references.
- `add_contenttype_file_caps.php` - inserts minimal `contenttype/file:*` capabilities into `mdl_capabilities` and purges caches.

Backups created during the cleanup are stored alongside these scripts with filenames like
`backup_config_plugins_ollama_YYYYMMDD_HHMMSS.json`.

Usage examples:
- Dry-run find: `php check_leftover_ollama.php`
- Dry-run delete: `php remove_ollama_config_plugins.php`
- Confirm delete: `php remove_ollama_config_plugins.php --confirm`
- Dry-run insert caps: `php add_contenttype_file_caps.php`
- Confirm insert: `php add_contenttype_file_caps.php --confirm`

Keep or remove these tools as preferred. They are safe to run but always check the backups before making destructive changes.
# AutoCurriculum Diagnostic Tools

Purpose: helper CLI scripts used during recent maintenance to locate and remove stale "ollama" configuration and to manage capability registration. These are diagnostics and safe-to-run utilities; keep them under `local/autocurriculum/tools/`.

Files moved here:
- `check_leftover_ollama.php` — scan DB and local plugin dirs for "ollama" references (read-only).
- `remove_ollama_config_plugins.php` — backup and (optionally) delete `config_plugins` rows matching "ollama" (dry-run by default).
- `delete_aiprovider_ollama_config.php` — delete `config_plugins` rows specifically where `plugin = 'aiprovider_ollama'` (used after backup).
- `check_capabilities.php` — verify capability names in `mdl_capabilities`.
- `dump_capabilities_schema.php` — show capabilities table schema and sample row.
- `list_contenttype_caps.php` — list `contenttype/*` capabilities.
- `add_contenttype_file_caps.php` — insert `contenttype/file` capability rows if missing (and purge caches).

Backups created during work:
- `local/autocurriculum/backup_config_plugins_ollama_*.json` — backup of `config_plugins` rows before deletion.
- `local/autocurriculum/backup_ai_providers_ollama_*.json` — backup of `ai_providers` rows (if present earlier).

Notes:
- These are helper tools and not required for normal operation. You may keep them for future diagnostics or remove them later. They are intentionally placed in `local/autocurriculum/tools/` to make their purpose clear.

Usage examples (run from repository root):
```pwsh
d:\Moodle\server\php\php.exe d:\Moodle\server\moodle\local\autocurriculum\tools\check_leftover_ollama.php
d:\Moodle\server\php\php.exe d:\Moodle\server\moodle\local\autocurriculum\tools\add_contenttype_file_caps.php
```

If you want these removed or committed to a VCS, tell me and I'll prepare a commit-ready patch or delete them.
