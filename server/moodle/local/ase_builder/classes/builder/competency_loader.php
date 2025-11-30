<?php
namespace local_ase_builder\builder;

defined('MOODLE_INTERNAL') || die();

use core_competency\api as competency_api;

/**
 * Loads ASE / AED competency frameworks from JSON descriptors.
 *
 * NOTE: This is a minimal example implementation. You can safely extend
 * this to support updates, versioning, and additional frameworks.
 */
class competency_loader
{

    /**
     * Import frameworks from the plugin's data JSON files.
     *
     * @return void
     */
    public function import_all(): void
    {
        global $CFG;

        $datapath = $CFG->dirroot . '/local/ase_builder/data';

        $files = [
            'ase.json' => 'ASE Automotive Service Excellence',
            'aed.json' => 'AED Diesel Equipment Technology',
        ];

        foreach ($files as $file => $description) {
            $full = $datapath . '/' . $file;
            if (!file_exists($full)) {
                continue;
            }
            $json = json_decode(file_get_contents($full), true);
            if (!$json || empty($json['competencies'])) {
                continue;
            }

            // Very lightweight example: in production you would check
            // if the framework already exists, handle updates, etc.
            $shortcode = $json['code'] ?? pathinfo($file, PATHINFO_FILENAME);

            $framework = competency_api::create_framework(
                (object)[
                'shortname'   => $shortcode,
                'idnumber'    => $shortcode,
                'description' => $description,
                'scaleid'     => 1, // Default scale; adjust per site policy.
                'visible'     => 1,
                ]
            );

            foreach ($json['competencies'] as $idx => $comp) {
                competency_api::create_competency(
                    (object)[
                    'shortname'     => $comp['shortname'],
                    'idnumber'      => $comp['idnumber'],
                    'description'   => $comp['description'] ?? '',
                    'frameworkid'   => $framework->get('id'),
                    'sortorder'     => $comp['sortorder'] ?? $idx,
                    'visible'       => 1,
                    ]
                );
            }
        }
    }
}
