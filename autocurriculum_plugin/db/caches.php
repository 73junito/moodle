<?php
// File: db/caches.php

defined('MOODLE_INTERNAL') || die();

$definitions = array(
    'ratelimit' => array(
        'mode' => cache_store::MODE_APPLICATION,
        'simplekeys' => true,
        'simpledata' => true,
        'ttl' => 3600,
    ),
    'apiresponses' => array(
        'mode' => cache_store::MODE_APPLICATION,
        'simplekeys' => true,
        'simpledata' => false,
        'ttl' => 3600,
    ),
);
