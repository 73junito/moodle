<?php
namespace local_ase_builder\builder;

defined('MOODLE_INTERNAL') || die();

/**
 * Section builder for creating topic sections with rich layouts.
 */
class section_builder
{

    /**
     * Ensure a course has at least the requested number of sections.
     *
     * @param  \stdClass $course
     * @param  int       $numsections
     * @return void
     */
    public function ensure_sections(\stdClass $course, int $numsections): void
    {
        global $CFG;

        include_once $CFG->dirroot . '/course/lib.php';

        if ($numsections < 1) {
            $numsections = 1;
        }

        $sections = range(1, $numsections);
        if (function_exists('course_create_sections_if_missing')) {
            course_create_sections_if_missing($course, $sections);
        }
    }

    /**
     * Apply a named layout to the course sections.
     *
     * Each layout entry becomes the title of one section (starting at 1).
     *
     * @param  \stdClass $course
     * @param  array     $layout
     * @return void
     */
    public function apply_layout(\stdClass $course, array $layout): void
    {
        global $DB;

        if (empty($layout)) {
            return;
        }

        $numsections = count($layout);
        $this->ensure_sections($course, $numsections);

        // Fetch sections for this course.
        $sections = $DB->get_records('course_sections', ['course' => $course->id], 'section ASC');

        foreach ($layout as $index => $title) {
            $sectionnum = $index + 1; // Sections are 1-based (0 is general).
            foreach ($sections as $section) {
                if ((int)$section->section === $sectionnum) {
                    $section->name = $title;
                    // Keep summary minimal; you can populate outcomes here later.
                    if (!isset($section->summary) || trim($section->summary) === '') {
                        $section->summary = '';
                        $section->summaryformat = FORMAT_HTML;
                    }
                    $DB->update_record('course_sections', $section);
                    break;
                }
            }
        }
    }
}
