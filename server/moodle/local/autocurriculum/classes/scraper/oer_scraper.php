<?php
namespace local_ase_builder\scraper;

defined('MOODLE_INTERNAL') || die();

/**
 * Base OER scraper.
 *
 * This class documents the interface used by the course builder.
 * Implement search() in child classes using APIs or curated datasets
 * in compliance with provider terms of use.
 */
abstract class oer_scraper
{

    /**
     * Search for OER resources by keyword or tag.
     *
     * @param  string $query
     * @return array List of associative arrays describing resources.
     */
    abstract public function search(string $query): array;

    /**
     * Helper to normalise a generic resource array.
     *
     * @param  array $data
     * @return array
     */
    protected function normalise(array $data): array
    {
        return [
            'title'       => $data['title']       ?? '',
            'description' => $data['description'] ?? '',
            'url'         => $data['url']         ?? '',
            'license'     => $data['license']     ?? '',
            'source'      => $data['source']      ?? static::class,
        ];
    }
}
