<?php
namespace local_ase_builder\utils;

defined('MOODLE_INTERNAL') || die();

/**
 * Simple metadata DTO for tracking accreditation / OER provenance.
 */
class metadata
{
    /**
     * @var string|null 
     */
    public $frameworkcode; // e.g., ASE A1, AED, etc.
    /**
     * @var string|null 
     */
    public $source;        // e.g., SkillsCommons, ATE Central.
    /**
     * @var string|null 
     */
    public $sourceurl;
    /**
     * @var string|null 
     */
    public $license;
    /**
     * @var string|null 
     */
    public $version;       // e.g., 2025.1

    public function __construct(array $data = [])
    {
        foreach ($data as $k => $v) {
            if (property_exists($this, $k)) {
                $this->$k = $v;
            }
        }
    }

    /**
     * Export as JSON-safe associative array.
     *
     * @return array
     */
    public function export(): array
    {
        return [
            'frameworkcode' => $this->frameworkcode,
            'source'        => $this->source,
            'sourceurl'     => $this->sourceurl,
            'license'       => $this->license,
            'version'       => $this->version,
        ];
    }
}
