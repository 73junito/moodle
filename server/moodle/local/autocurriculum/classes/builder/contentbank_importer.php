<?php
namespace local_ase_builder\builder;

defined('MOODLE_INTERNAL') || die();

/**
 * Content bank import logic.
 *
 * In a production deployment you would use Moodle's content bank APIs
 * to import H5P, SCORM, and other assets discovered by the scraper
 * classes. This class wires the scraper outputs into a single point.
 */
class contentbank_importer {

    /**
     * Import a list of resources into the content bank or course.
     *
     * @param int   $courseid
     * @param array $resources Normalised OER resource arrays.
     * @return void
     */
    public function import(int $courseid, array $resources): void {
        // This is intentionally conservative: instead of performing
        // remote downloads by default, we simply document where the
        // resources would be imported. You can extend this class to:
        //
        // - Download H5P/SCORM packages into file storage.
        // - Create content bank entries via core_contentbank APIs.
        // - Create URL resources in the course linking to OER.
        //
        // The wiring from the scraper layer into this importer is
        // implemented in course_builder.
        if (empty($resources)) {
            return;
        }

        // Example: you might log the fact that resources are available
        // for this course, or selectively import only H5P/SCORM types.
    }
}
