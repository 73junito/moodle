<?php
namespace local_ase_builder\scraper;

defined('MOODLE_INTERNAL') || die();

use \curl;

/**
 * OpenStax-specific scraper.
 * Uses OpenStax API to search for textbooks.
 */
class openstax extends oer_scraper {

    /**
     * {@inheritdoc}
     */
    public function search(string $query): array {
        $curl = new \curl();
        $url = 'https://openstax.org/api/v1/books';
        $response = $curl->get($url);

        if ($curl->get_errno()) {
            return [];
        }

        $books = json_decode($response, true);
        if (!is_array($books)) {
            return [];
        }

        $results = [];
        foreach ($books as $book) {
            if (stripos($book['title'] ?? '', $query) !== false) {
                $results[] = $this->normalise([
                    'title' => $book['title'] ?? '',
                    'description' => $book['description'] ?? '',
                    'url' => 'https://openstax.org/details/books/' . ($book['slug'] ?? ''),
                    'license' => 'CC BY',
                    'source' => 'OpenStax',
                ]);
            }
        }

        return $results;
    }
}
