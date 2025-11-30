<?php

namespace local_autocurriculum\event;

defined('MOODLE_INTERNAL') || die();

class LabGenerated extends \core\event\base
{
    protected function init()
    {
        $this->data['crud'] = 'c';
        $this->data['edulevel'] = self::LEVEL_TEACHING;
        $this->data['objecttable'] = 'local_autocurriculum_labs';
    }

    public function getName()
    {
        return get_string('event_lab_generated', 'local_autocurriculum');
    }

    public function getDescription()
    {
        return "The user with id {$this->userid} generated a lab for section {$this->objectid} in course {$this->courseid}.";
    }
}
