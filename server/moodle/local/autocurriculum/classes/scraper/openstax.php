<?php
namespace local_ase_builder\scraper;

defined('MOODLE_INTERNAL') || die();

/**
 * OpenStax-specific scraper stub.
 */
class openstax extends oer_scraper {

    /**
     * {@inheritdoc}
     */
    public function search(string $query): array {
        // Stub: you can hard-code known ISBNs / titles or call catalog APIs.
        return [];
    }
}
