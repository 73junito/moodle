<?php
// File: lang/en/local_autocurriculum.php

$string['pluginname'] = 'AutoCurriculum';
$string['nav_generatelabs'] = 'Generate Virtual Labs';
$string['nav_generatelabs_desc'] = 'Automatically generate Virtual Garage labs for this course.';
$string['generatedlabs_success'] = 'Generated {$a} virtual labs successfully.';
$string['generatedlabs_none'] = 'No labs were generated.';
$string['ollama_url'] = 'Ollama Server URL';
$string['ollama_url_desc'] = 'URL of the Ollama server for generating lab scenarios.';
$string['default_model'] = 'Default Ollama Model';
$string['default_model_desc'] = 'Default model to use for lab generation (e.g., llama3, qwen2.5).';
$string['generatelabs'] = 'Generate Labs';
$string['generatelabs_desc'] = 'Generate virtual labs for course sections using AI.';

$string['activation_title'] = 'Next Steps to Activate';
$string['activation_install_plugins'] = 'Install Plugins: Go to Site Administration → Plugins → Install plugins. Upload/install local_autocurriculum first, then mod_virtualgarage. Visit Site Administration → Notifications to complete installation and create database tables.';
$string['activation_configure'] = 'Configure Settings: In Site Administration → Plugins → Local plugins → AutoCurriculum, set the Ollama server URL and default model.';
$string['activation_generate'] = 'Generate Labs: Teachers with editing rights will see "Generate Virtual Labs" in the course navigation to create AI-powered virtual lab scenarios.';
$string['activation_unity'] = 'Unity Integration: Import the `Assets/` folder into a Unity 6 project, build for WebGL and host the build in Moodle under /mod/virtualgarage/build/.';
$string['settings_heading'] = 'AutoCurriculum Settings';
$string['settings_saved'] = 'Settings saved';
$string['settings_savefail'] = 'Failed to save settings';

$string['select_sections'] = 'Select sections to generate labs for';
$string['custom_prompt'] = 'Custom prompt (optional)';
$string['generate'] = 'Generate Labs';
$string['ollama_not_configured'] = 'Ollama is not configured.';
$string['generation_failed'] = 'Failed to generate lab for section {$a}.';

$string['bulk_generatelabs'] = 'Bulk Generate Labs';
$string['select_courses'] = 'Select courses to generate labs for';
$string['generate_bulk'] = 'Generate Labs for Selected Courses';
$string['bulk_generated_success'] = 'Generated labs for {$a} sections successfully.';
$string['bulk_generated_none'] = 'No labs were generated.';

$string['auto_generate_labs'] = 'Auto-generate labs for new courses';
$string['auto_generate_labs_desc'] = 'Automatically generate virtual labs for all sections when a new course is created, if the creator has the capability.';

$string['event_lab_generated'] = 'Lab generated';
$string['nav_scan'] = 'Scan for Labs';
$string['nav_scan_desc'] = 'Scan selected course sections for existing lab scenarios.';
$string['scan_results'] = 'Scan Results';
$string['no_labs_found'] = 'No existing labs found for the selected sections.';
$string['labs_found'] = 'Found {$a} labs in the selected sections.';
$string['scan_courses'] = 'Scan Courses';
$string['scan_courses_desc'] = 'Scan all courses for missing descriptions, lessons, syllabus, and question banks.';
$string['missing_description'] = 'Missing description';
$string['missing_lessons'] = 'Missing lessons';
$string['missing_syllabus'] = 'Missing syllabus';
$string['missing_question_banks'] = 'Missing question banks';
$string['no_missing_items'] = 'No missing items found.';
