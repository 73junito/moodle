<?php
namespace local_ase_builder\utils;

defined('MOODLE_INTERNAL') || die();

/**
 * Handles license validation and normalization for imported OER.
 */
class license
{
    /**
     * @var array Allowed licenses. 
     */
    protected $allowed = [
        'CC-BY',
        'CC BY',
        'CC-BY-SA',
        'CC0',
        'PUBLIC DOMAIN',
    ];

    /**
     * Normalize a raw license string.
     *
     * @param  string $raw
     * @return string|null
     */
    public function normalize(string $raw): ?string
    {
        $raw = trim(strtoupper($raw));
        foreach ($this->allowed as $allowed) {
            if (strpos($raw, $allowed) !== false) {
                return $allowed;
            }
        }
        if ($raw === '') {
            return null;
        }
        // Fallback: treat clearly open statements as CC-BY.
        if (strpos($raw, 'ATTRIBUTION') !== false || strpos($raw, 'CC') !== false) {
            return 'CC-BY';
        }
        return null;
    }

    /**
     * Check if a license is permitted for import.
     *
     * @param  string $license
     * @return bool
     */
    public function is_allowed(string $license): bool
    {
        return in_array($this->normalize($license), $this->allowed, true);
    }
}
