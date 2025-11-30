<?php
namespace local_ase_builder\scraper;

defined('MOODLE_INTERNAL') || die();

/**
 * ATE Central-specific scraper stub.
 */
class ate_central extends oer_scraper {

    /**
     * {@inheritdoc}
     */
    public function search(string $query): array {
        // Stub: implement using ATE Central feeds or APIs where permitted.
        return [];
    }
}
