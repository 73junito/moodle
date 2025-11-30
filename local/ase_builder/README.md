# ASE / AED Program Builder

This Moodle local plugin automates the creation of courses for Automotive Service Excellence (ASE) and Automotive and Diesel Education (AED) programs.

## Features

- Auto-generates courses with sections based on ASE/AED standards.
- Imports Open Educational Resources (OER) from SkillsCommons, ATE Central, and OpenStax.
- Populates question banks and competencies.
- Asynchronous building via Moodle tasks.

## Installation

1. Place the plugin in `local/ase_builder`.
2. Run the Moodle upgrade.
3. Configure settings in Site Administration > Plugins > Local plugins > ASE / AED Program Builder.
4. Optionally enable auto-build on install.

## Usage

- Access the dashboard at `/local/ase_builder/`.
- Click "Run Builder" to queue course creation.
- Monitor task progress in Moodle's task logs.

## Requirements

- Moodle 4.5+
- PHP 7.4+

## License

GPL v3