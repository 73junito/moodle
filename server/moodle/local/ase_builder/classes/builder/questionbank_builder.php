<?php
namespace local_ase_builder\builder;

defined('MOODLE_INTERNAL') || die();

/**
 * Question bank builder logic.
 *
 * This implementation supports importing Moodle XML files stored under:
 *   local/ase_builder/data/questionbank/
 *
 * File naming convention (first match wins):
 *   - {shortname}.xml      e.g., ASE-A1.xml
 *   - {coursecode}.xml     e.g., ASE A1.xml (spaces replaced with _)
 */
class questionbank_builder
{

    /**
     * Build question categories and import XML for a given course.
     *
     * @param  int    $courseid
     * @param  string $coursecode      Human-readable code, e.g. "ASE A1".
     * @param  string $courseshortname Shortname, e.g. "ASE-A1".
     * @return void
     */
    public function build_for_course(int $courseid, string $coursecode, string $courseshortname): void
    {
        global $CFG, $DB;

        $datadir = $CFG->dirroot . '/local/ase_builder/data/questionbank';

        // Determine candidate XML filenames.
        $candidates = [];
        $candidates[] = $datadir . '/' . $courseshortname . '.xml';
        $candidates[] = $datadir . '/' . str_replace(' ', '_', $coursecode) . '.xml';

        $filepath = null;
        foreach ($candidates as $candidate) {
            if (file_exists($candidate)) {
                $filepath = $candidate;
                break;
            }
        }

        if (!$filepath) {
            // No XML available for this course; nothing to import.
            return;
        }

        include_once $CFG->dirroot . '/question/editlib.php';
        include_once $CFG->dirroot . '/question/format.php';
        include_once $CFG->dirroot . '/question/format/xml/format.php';

        $context = \context_course::instance($courseid);

        // Find or create a question category for this course.
        $catname = $courseshortname . ' Question Bank';
        $category = $DB->get_record(
            'question_categories', [
            'name'      => $catname,
            'contextid' => $context->id,
            ]
        );

        if (!$category) {
            $category = (object)[
                'name'        => $catname,
                'contextid'   => $context->id,
                'info'        => 'Imported from ASE Builder XML for ' . $coursecode,
                'infoformat'  => FORMAT_HTML,
                'stamp'       => make_unique_id_code(),
                'parent'      => 0,
                'sortorder'   => 999,
                'idnumber'    => $courseshortname,
            ];
            $category->id = $DB->insert_record('question_categories', $category);
        }

        $qformat = new \qformat_xml();
        $qformat->setCategory($category);
        $qformat->setContexts([$context]);
        $qformat->setFilename($filepath);
        $qformat->setMatchgrades('error');
        $qformat->setStoponerror(false);
        $qformat->setCatfromfile(false);
        $qformat->setContextfromfile(false);

        if ($qformat->importpreprocess()) {
            $content = file_get_contents($filepath);
            $qformat->importprocess($content);
            $qformat->importpostprocess();
        }
    }
}
