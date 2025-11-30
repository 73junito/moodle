# AutoCurriculum Plugin for Moodle

## Features
- AI-powered lab generation using Ollama
- Bulk generation for multiple courses
- Auto-generation on course creation
- Dashboard block for quick access
- Custom course format for integrated display
- Virtual Garage module for Unity integration

## Installation
1. Install plugins in order: local_autocurriculum, block_autocurriculum, format_autocurriculum, mod_virtualgarage
2. Configure Ollama settings
3. Enable auto-generation if desired

## Usage
- Use bulk generation for existing courses
- Add block to dashboard
- Change course format to AutoCurriculum
- Create Virtual Garage activities

## Troubleshooting
- Ensure Ollama is running and accessible
- Check PHP cURL extension
- Verify capabilities for users

## API
Ollama endpoint: /api/generate with model and prompt

## Next Steps to Activate

1. Install Plugins in Moodle:
• Go to Site Administration → Plugins → Install plugins.
• Upload/install `local_autocurriculum` first, then `mod_virtualgarage`, `block_autocurriculum`, and `format_autocurriculum`.
• Visit Site Administration → Notifications to complete installation and create database tables.

2. Configure Settings:
• In Site Administration → Plugins → Local plugins → AutoCurriculum, set the Ollama server URL (e.g., http://localhost:11434) and default model (e.g., llama3).

3. Generate Labs:
• In any course, teachers with editing rights will see "Generate Virtual Labs" in the course navigation.
• Click it to open the form, select sections/topics, and generate AI-powered virtual lab scenarios.
• Generated labs are stored in the database for the selected sections.

4. Dashboard Integration:
• The AutoCurriculum Labs block can be added to user dashboards (My Moodle) to display recent generated labs.
• Go to Site Administration → Plugins → Blocks → Manage blocks to enable it, then users can add it via the "Add a block" button.
• The block footer links to bulk generation for all accessible courses.

5. Course Display:
• To display generated labs directly in course sections, change the course format to "AutoCurriculum format" in Course settings.
• This format shows generated labs alongside activities in each section.

6. Bulk and Auto-Generation:
• Use the bulk generation page (linked from the block) to generate labs for multiple courses at once.
• Enable auto-generation in plugin settings to automatically create labs for new courses.

7. Unity Integration:
• The Unity scripts are ready in the workspace (Assets/ folder).
• Import them into a Unity 6 project, build for WebGL, and host the build in Moodle's web root (e.g., `/mod/virtualgarage/build/`).

The plugin suite now includes full functionality for generating, storing, and displaying AI-powered virtual labs. If you encounter any issues during installation or need the Unity project set up, let me know!
