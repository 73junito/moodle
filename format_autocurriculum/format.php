<?php
defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/course/format/lib.php');

$course = $DB->get_record('course', array('id' => $course->id), '*', MUST_EXIST);
$format = course_get_format($course);
$modinfo = get_fast_modinfo($course);
$sections = $modinfo->get_section_info_all();

$templatecontext = [
    'course' => $course,
    'sections' => [],
];

foreach ($sections as $section) {
    if (!$section->uservisible) {
        continue;
    }

    $sectioncontext = [
        'number' => $section->section,
        'name' => $format->get_section_name($section),
        'summary' => $section->summary,
        'modules' => [],
    ];

    // Get generated lab for this section.
    $lab = $DB->get_record('local_autocurriculum_labs', array('courseid' => $course->id, 'sectionid' => $section->id));
    if ($lab) {
        $sectioncontext['generatedlab'] = [
            'content' => $lab->content,
            'timecreated' => userdate($lab->timecreated),
        ];
    }

    // Add modules.
    $cms = $modinfo->get_cms();
    foreach ($cms as $cm) {
        if ($cm->section == $section->id) {
            $sectioncontext['modules'][] = [
                'name' => $cm->name,
                'url' => $cm->url,
            ];
        }
    }

    $templatecontext['sections'][] = $sectioncontext;
}

// Render using template.
echo $OUTPUT->render_from_template('format_autocurriculum/course', $templatecontext);