<?php
namespace local_ase_builder\scraper;

defined('MOODLE_INTERNAL') || die();

/**
 * SkillsCommons-specific scraper stub.
 *
 * Replace the implementation of search() with calls to SkillsCommons
 * search endpoints or curated CSV/JSON that you maintain offline.
 */
class skillscommons extends oer_scraper
{

    /**
     * {@inheritdoc}
     */
    public function search(string $query): array
    {
        // Stub: return an empty list until you implement SkillsCommons lookups.
        return [];
    }
}
