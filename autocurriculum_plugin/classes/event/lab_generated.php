<?php
namespace local_autocurriculum\event;

defined('MOODLE_INTERNAL') || die();

class lab_generated extends \core\event\base
{
    protected function init()
    {
        $this->data['crud'] = 'c';
        $this->data['edulevel'] = self::LEVEL_TEACHING;
        $this->data['objecttable'] = 'local_autocurriculum_labs';
    }

    public static function get_name()
    {
        return get_string('event_lab_generated', 'local_autocurriculum');
    }

    public function get_description()
    {
        return "The user with id {$this->userid} generated a lab for section {$this->objectid} in course {$this->courseid}.";
    }
}