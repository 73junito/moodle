<?php
namespace local_ase_builder\utils;

defined('MOODLE_INTERNAL') || die();

/**
 * Maps ASE / AED task lists to Moodle course / section / activity identifiers.
 *
 * This version includes richer default layouts (section names) for:
 * - ASE A1–A8 (Automotive)
 * - ASE T1–T8 (Medium/Heavy Truck)
 * - AED Diesel core areas
 */
class mapper
{

    /**
     * Get default ASE Automotive course mappings (A1–A8).
     *
     * @return array
     */
    public function get_ase_course_map(): array
    {
        return [
            'ASE A1' => [
                'shortname'   => 'ASE-A1',
                'fullname'    => 'ASE A1 – Engine Repair',
                'summary'     => 'Auto-generated shell aligned to ASE A1 Engine Repair tasks.',
                'layout'      => [
                    'Program Orientation & Safety',
                    'Engine Fundamentals & Identification',
                    'Cylinder Head & Valve Train Service',
                    'Lubrication & Cooling Systems',
                    'Short Block Disassembly & Inspection',
                    'Short Block Assembly',
                    'Engine Diagnostics & Performance',
                    'Review & ASE A1 Exam Preparation',
                ],
            ],
            'ASE A2' => [
                'shortname'   => 'ASE-A2',
                'fullname'    => 'ASE A2 – Automatic Transmission/Transaxle',
                'summary'     => 'Automatic transmission/transaxle fundamentals, operation, and diagnostics.',
                'layout'      => [
                    'Orientation, Safety & Transmission Overview',
                    'Hydraulic & Electronic Control Systems',
                    'Torque Converter Operation & Diagnosis',
                    'Transmission Disassembly & Inspection',
                    'Clutch Packs, Bands & Servos',
                    'Valve Body Operation & Service',
                    'Transmission Reassembly & Testing',
                    'Review & ASE A2 Exam Preparation',
                ],
            ],
            'ASE A3' => [
                'shortname'   => 'ASE-A3',
                'fullname'    => 'ASE A3 – Manual Drive Train & Axles',
                'summary'     => 'Manual transmissions, clutches, differentials, and driveline service.',
                'layout'      => [
                    'Orientation, Safety & Drivetrain Overview',
                    'Clutch Systems Operation & Diagnosis',
                    'Manual Transmission Service',
                    'Transaxles & Transfer Cases',
                    'Drive Axles & Differentials',
                    'Driveline Components & Service',
                    'Noise, Vibration & Harshness Diagnosis',
                    'Review & ASE A3 Exam Preparation',
                ],
            ],
            'ASE A4' => [
                'shortname'   => 'ASE-A4',
                'fullname'    => 'ASE A4 – Suspension & Steering',
                'summary'     => 'Suspension and steering systems diagnosis, repair, and alignment.',
                'layout'      => [
                    'Orientation, Safety & Chassis Overview',
                    'Steering Systems',
                    'Front Suspension',
                    'Rear Suspension',
                    'Wheel Alignment Theory',
                    'Alignment Procedures & Adjustments',
                    'Electronic Steering & Chassis Controls',
                    'Review & ASE A4 Exam Preparation',
                ],
            ],
            'ASE A5' => [
                'shortname'   => 'ASE-A5',
                'fullname'    => 'ASE A5 – Brakes',
                'summary'     => 'Hydraulic, disc, drum, and ABS brake systems service.',
                'layout'      => [
                    'Orientation, Brake Safety & Fundamentals',
                    'Hydraulic System Operation & Service',
                    'Disc Brake Systems',
                    'Drum Brake Systems',
                    'Parking Brake Systems',
                    'ABS & Stability Control Fundamentals',
                    'Brake System Diagnosis & Repair',
                    'Review & ASE A5 Exam Preparation',
                ],
            ],
            'ASE A6' => [
                'shortname'   => 'ASE-A6',
                'fullname'    => 'ASE A6 – Electrical/Electronic Systems',
                'summary'     => 'Electrical and electronic diagnosis and repair.',
                'layout'      => [
                    'Orientation, Electrical Safety & Theory',
                    'Meters, Wiring Diagrams & Diagnostic Tools',
                    'Battery Testing & Service',
                    'Starting System Diagnosis',
                    'Charging System Diagnosis',
                    'Lighting & Accessory Circuits',
                    'Body Electronics & Network Systems (CAN)',
                    'Review & ASE A6 Exam Preparation',
                ],
            ],
            'ASE A7' => [
                'shortname'   => 'ASE-A7',
                'fullname'    => 'ASE A7 – Heating & Air Conditioning',
                'summary'     => 'Automotive HVAC fundamentals and diagnostics.',
                'layout'      => [
                    'Orientation, HVAC Safety & Fundamentals',
                    'Refrigeration Cycle & Components',
                    'Heating Systems',
                    'Manual HVAC Systems',
                    'Automatic Climate Control',
                    'Diagnostics & Performance Testing',
                    'HVAC System Service Procedures',
                    'Review & ASE A7 Exam Preparation',
                ],
            ],
            'ASE A8' => [
                'shortname'   => 'ASE-A8',
                'fullname'    => 'ASE A8 – Engine Performance',
                'summary'     => 'Ignition, fuel, emissions, and engine performance.',
                'layout'      => [
                    'Orientation, Safety & Engine Management Overview',
                    'Ignition Systems',
                    'Fuel Delivery & Fuel Injection',
                    'Air Induction & Exhaust Systems',
                    'Emission Control Systems',
                    'OBD-II & Scan Tool Strategies',
                    'Driveability Diagnosis & Case Studies',
                    'Review & ASE A8 Exam Preparation',
                ],
            ],
        ];
    }

    /**
     * Get default ASE Medium/Heavy Truck course mappings (T1–T8).
     *
     * @return array
     */
    public function get_truck_course_map(): array
    {
        return [
            'ASE T1' => [
                'shortname' => 'ASE-T1',
                'fullname'  => 'ASE T1 – Gasoline Engines (Medium/Heavy Truck)',
                'summary'   => 'Gasoline engine diagnosis and repair in truck applications.',
                'layout'    => [
                    'Orientation, Safety & Engine Overview',
                    'Engine Mechanical Fundamentals',
                    'Fuel & Ignition Systems',
                    'Air Induction & Exhaust Systems',
                    'Lubrication & Cooling',
                    'Electronic Engine Controls',
                    'Diagnosis & Performance Testing',
                    'Review & ASE T1 Exam Preparation',
                ],
            ],
            'ASE T2' => [
                'shortname' => 'ASE-T2',
                'fullname'  => 'ASE T2 – Diesel Engines',
                'summary'   => 'Diesel engine construction, operation, and diagnostics.',
                'layout'    => [
                    'Orientation, Safety & Diesel Engine Fundamentals',
                    'Cylinder Head, Valves & Valve Train',
                    'Cylinder Block, Pistons & Rods',
                    'Lubrication & Cooling Systems',
                    'Air Management & Turbocharging',
                    'Exhaust Aftertreatment Systems',
                    'Diesel Engine Diagnostics',
                    'Review & ASE T2 Exam Preparation',
                ],
            ],
            'ASE T3' => [
                'shortname' => 'ASE-T3',
                'fullname'  => 'ASE T3 – Drive Train',
                'summary'   => 'Truck transmissions, clutches and drivelines.',
                'layout'    => [
                    'Orientation, Safety & Drivetrain Overview',
                    'Clutch Systems',
                    'Manual Transmissions & Transaxles',
                    'Automated & Automatic Transmissions',
                    'Drive Axles & Differentials',
                    'Driveline Components',
                    'Drivetrain Diagnostics',
                    'Review & ASE T3 Exam Preparation',
                ],
            ],
            'ASE T4' => [
                'shortname' => 'ASE-T4',
                'fullname'  => 'ASE T4 – Brakes',
                'summary'   => 'Air and hydraulic brake systems and diagnostics.',
                'layout'    => [
                    'Orientation, Brake Safety & Fundamentals',
                    'Air Brake System Components',
                    'Air Brake Controls & Valves',
                    'Foundation Brakes',
                    'Parking Brakes & Auxiliary Systems',
                    'ABS & Stability Control',
                    'Brake System Diagnostics & Testing',
                    'Review & ASE T4 Exam Preparation',
                ],
            ],
            'ASE T5' => [
                'shortname' => 'ASE-T5',
                'fullname'  => 'ASE T5 – Suspension & Steering',
                'summary'   => 'Truck steering and suspension systems.',
                'layout'    => [
                    'Orientation, Safety & Chassis Overview',
                    'Steering Gear & Linkage',
                    'Power Steering Systems',
                    'Front Suspension',
                    'Rear Suspension',
                    'Alignment Theory & Procedures',
                    'Steering & Suspension Diagnostics',
                    'Review & ASE T5 Exam Preparation',
                ],
            ],
            'ASE T6' => [
                'shortname' => 'ASE-T6',
                'fullname'  => 'ASE T6 – Electrical/Electronic Systems',
                'summary'   => 'Truck electrical power, cranking, charging, and chassis electronics.',
                'layout'    => [
                    'Orientation, Electrical Safety & Theory',
                    'Wiring Diagrams, Meters & Tools',
                    'Batteries & Power Distribution',
                    'Starting Systems',
                    'Charging Systems',
                    'Lighting & Accessory Circuits',
                    'Multiplexing & Data Networks',
                    'Review & ASE T6 Exam Preparation',
                ],
            ],
            'ASE T7' => [
                'shortname' => 'ASE-T7',
                'fullname'  => 'ASE T7 – Heating, Ventilation & Air Conditioning',
                'summary'   => 'Truck HVAC systems and diagnostics.',
                'layout'    => [
                    'Orientation, HVAC Safety & Fundamentals',
                    'Refrigeration Cycle & Components',
                    'Heating Systems',
                    'Truck HVAC Controls',
                    'Service Procedures & Recovery',
                    'Performance Testing & Diagnostics',
                    'Integrated HVAC Case Studies',
                    'Review & ASE T7 Exam Preparation',
                ],
            ],
            'ASE T8' => [
                'shortname' => 'ASE-T8',
                'fullname'  => 'ASE T8 – Preventive Maintenance Inspection',
                'summary'   => 'PMI procedures and documentation.',
                'layout'    => [
                    'Orientation, Safety & PMI Overview',
                    'Engine & Drivetrain PMI',
                    'Brake System PMI',
                    'Steering & Suspension PMI',
                    'Electrical & Lighting PMI',
                    'Body, Frame & Coupling PMI',
                    'PMI Documentation & Compliance',
                    'Review & ASE T8 Exam Preparation',
                ],
            ],
        ];
    }

    /**
     * Get AED Diesel course mappings.
     *
     * @return array
     */
    public function get_aed_course_map(): array
    {
        return [
            'AED DIESEL ENGINES' => [
                'shortname' => 'AED-ENG',
                'fullname'  => 'AED – Diesel Engines',
                'summary'   => 'AED-aligned diesel engine theory, service and diagnostics.',
                'layout'    => [
                    'Orientation, Safety & Diesel Fundamentals',
                    'Engine Identification & Specifications',
                    'Valve Train & Cylinder Head Service',
                    'Short Block Service',
                    'Lubrication & Cooling Systems',
                    'Air Management & Turbocharging',
                    'Engine Performance & Emissions',
                    'Review & AED Diesel Engines',
                ],
            ],
            'AED ELECTRICAL SYSTEMS' => [
                'shortname' => 'AED-ELEC',
                'fullname'  => 'AED – Electrical Systems',
                'summary'   => 'Starting, charging, and electrical distribution systems.',
                'layout'    => [
                    'Orientation, Electrical Safety & Fundamentals',
                    'Wiring Diagrams & Diagnostic Tools',
                    'Batteries & Power Distribution',
                    'Starting Systems',
                    'Charging Systems',
                    'Chassis Electrical Systems',
                    'Electronic Controls & Networks',
                    'Review & AED Electrical Systems',
                ],
            ],
            'AED HYDRAULICS' => [
                'shortname' => 'AED-HYD',
                'fullname'  => 'AED – Hydraulics',
                'summary'   => 'Hydraulic theory and system service for diesel equipment.',
                'layout'    => [
                    'Orientation, Safety & Hydraulic Fundamentals',
                    'Hydraulic Components & Schematics',
                    'Pumps, Valves & Actuators',
                    'Hydraulic Diagnostics & Testing',
                    'Hose, Fitting & Seal Service',
                    'System Maintenance & Contamination Control',
                    'Integrated Hydraulic Systems',
                    'Review & AED Hydraulics',
                ],
            ],
        ];
    }
}
