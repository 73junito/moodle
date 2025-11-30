<?php
namespace local_ase_builder\task;

defined('MOODLE_INTERNAL') || die();

use local_ase_builder\builder\course_builder;

/**
 * Adhoc task to build ASE/AED courses asynchronously.
 */
class build_courses_task extends \core\task\adhoc_task
{

    /**
     * Execute the task.
     */
    public function execute()
    {
        $builder = new course_builder();
        $builder->build_all_programs();
    }

    /**
     * Get task name.
     *
     * @return string
     */
    public function get_name()
    {
        return get_string('buildcourses', 'local_ase_builder');
    }
}
