<?php
namespace local_ase_builder\builder;

defined('MOODLE_INTERNAL') || die();

use core_course_category;
use local_ase_builder\utils\mapper;
use local_ase_builder\builder\competency_loader;
use local_ase_builder\builder\section_builder;
use local_ase_builder\builder\contentbank_importer;
use local_ase_builder\builder\questionbank_builder;
use local_ase_builder\scraper\skillscommons;
use local_ase_builder\scraper\ate_central;
use local_ase_builder\scraper\openstax;
use local_ase_builder\utils\license as license_utils;

/**
 * Creates ASE / AED-aligned courses under the configured category.
 */
class course_builder {

    /**
     * Build all ASE / AED program courses.
     *
     * @return void
     */
    public function build_all_programs(): void {
        global $CFG;

        require_once($CFG->dirroot . '/course/lib.php');

        $config = get_config('local_ase_builder');
        $targetcategoryname = $config->targetcategory ?? 'Automotive & Diesel Technology';

        try {
            $category = $this->get_or_create_category($targetcategoryname);
        } catch (Exception $e) {
            debugging('Error creating category: ' . $e->getMessage(), DEBUG_DEVELOPER);
            return;
        }

        $mapper = new mapper();

        $coursespecs = array_merge(
            $mapper->get_ase_course_map(),
            $mapper->get_truck_course_map(),
            $mapper->get_aed_course_map()
        );

        foreach ($coursespecs as $code => $spec) {
            try {
                $this->create_or_update_course($category->id, $code, $spec);
            } catch (Exception $e) {
                debugging('Error building course ' . $code . ': ' . $e->getMessage(), DEBUG_DEVELOPER);
                continue;
            }
        }

        // Load competency frameworks from JSON.
        try {
            $loader = new competency_loader();
            $loader->import_all();
        } catch (Exception $e) {
            debugging('Error loading competencies: ' . $e->getMessage(), DEBUG_DEVELOPER);
        }
    }

    /**
     * Find or create the target course category.
     *
     * @param string $name
     * @return \core_course_category
     */
    protected function get_or_create_category(string $name): \core_course_category {
        $categories = core_course_category::get_all();
        foreach ($categories as $cat) {
            if (trim($cat->name) === trim($name)) {
                return $cat;
            }
        }

        return core_course_category::create([
            'name'     => $name,
            'idnumber' => 'ASE_AED_AUTO_DIESEL',
            'visible'  => 1,
            'parent'   => 0,
        ]);
    }

    /**
     * Create a course if it does not already exist, then:
     *  - apply a rich section layout
     *  - wire in OER resources to content bank importer
     *  - import any XML-based question bank
     *
     * @param int    $categoryid
     * @param string $code
     * @param array  $spec
     * @return void
     */
    protected function create_or_update_course(int $categoryid, string $code, array $spec): void {
        global $DB, $CFG;

        require_once($CFG->dirroot . '/course/lib.php');

        $shortname   = $spec['shortname'] ?? $code;
        $fullname    = $spec['fullname'] ?? $code;
        $summary     = $spec['summary'] ?? 'Auto-generated ASE / AED course shell.';
        $layout      = $spec['layout'] ?? [];
        $numsections = !empty($layout) ? count($layout) : ($spec['numsections'] ?? 8);

        if ($DB->record_exists('course', ['shortname' => $shortname])) {
            // For safety we do not modify existing courses automatically.
            return;
        }

        $course = (object)[
            'category'    => $categoryid,
            'shortname'   => $shortname,
            'fullname'    => $fullname,
            'summary'     => $summary,
            'format'      => 'topics',
            'numsections' => $numsections,
            'visible'     => 1,
        ];

        $created = create_course($course);

        // Apply section layout (topic names).
        $sectionbuilder = new section_builder();
        if (!empty($layout)) {
            $sectionbuilder->apply_layout($created, $layout);
        } else {
            $sectionbuilder->ensure_sections($created, $numsections);
        }

        // Discover OER resources for this course via scrapers.
        $resources = $this->find_oer_for_course($code);

        // Wire OER into content bank / course as needed.
        $contentimporter = new contentbank_importer();
        $contentimporter->import($created->id, $resources);

        // Import any available question bank XML for this course.
        $qb = new questionbank_builder();
        $qb->build_for_course($created->id, $code, $shortname);
    }

    /**
     * Use scraper classes to discover OER resources for a given course code.
     *
     * @param string $coursecode
     * @return array
     */
    protected function find_oer_for_course(string $coursecode): array {
        $resources = [];

        $config = get_config('local_ase_builder');
        $scrapers = [];

        if (!empty($config->enableskillscommons)) {
            $scrapers[] = new skillscommons();
        }
        if (!empty($config->enableatecentral)) {
            $scrapers[] = new ate_central();
        }
        if (!empty($config->enableopenstax)) {
            $scrapers[] = new openstax();
        }

        // You can refine these queries per course code or ASE task list.
        $queries = [
            $coursecode,
            $coursecode . ' automotive technology',
            $coursecode . ' diesel technology',
        ];

        foreach ($scrapers as $scraper) {
            foreach ($queries as $query) {
                try {
                    $resources = array_merge($resources, $scraper->search($query));
                } catch (Exception $e) {
                    debugging('Error searching ' . get_class($scraper) . ' for "' . $query . '": ' . $e->getMessage(), DEBUG_DEVELOPER);
                }
            }
        }

        // Filter by allowed licenses.
        $licenseutil = new license_utils();
        $filtered = [];
        foreach ($resources as $res) {
            $license = $res['license'] ?? '';
            if ($licenseutil->is_allowed($license)) {
                $filtered[] = $res;
            }
        }

        return $filtered;
    }
}
