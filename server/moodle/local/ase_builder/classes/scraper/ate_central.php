<?php
namespace local_ase_builder\scraper;

defined('MOODLE_INTERNAL') || die();

use \curl;

/**
 * ATE Central-specific scraper.
 * Uses ATE Central API to search for resources.
 */
class ate_central extends oer_scraper
{

    /**
     * {@inheritdoc}
     */
    public function search(string $query): array
    {
        $curl = new \curl();
        $url = 'https://atecentral.net/api/v1/resources/?q=' . urlencode($query);
        $response = $curl->get($url);

        if ($curl->get_errno()) {
            return [];
        }

        $data = json_decode($response, true);
        if (!is_array($data) || !isset($data['results']) || !is_array($data['results'])) {
            return [];
        }

        $results = [];
        foreach ($data['results'] as $item) {
            $results[] = $this->normalise(
                [
                'title' => $item['title'] ?? '',
                'description' => $item['description'] ?? '',
                'url' => $item['url'] ?? '',
                'license' => $item['license'] ?? '',
                'source' => 'ATE Central',
                ]
            );
        }

        return $results;
    }
}
