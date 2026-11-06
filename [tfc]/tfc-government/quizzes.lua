-- DMV quizzes: 5 multiple-choice questions each. `a` is the index (1-based) of the right answer.
-- Answers never leave the server: the client only gets the questions and choices.

GovQuizzes = {
    motorcycle = {
        { q = 'What should you always wear when riding a motorcycle?', c = { 'A helmet', 'Sunglasses', 'Nothing special', 'A backpack' }, a = 1 },
        { q = 'When is it legal to ride between lanes of stopped traffic?', c = { 'Always', 'Never in San Andreas', 'Only when it is safe and traffic is slow', 'Only at night' }, a = 3 },
        { q = 'Which brake gives most of your stopping power?', c = { 'Rear brake', 'Front brake', 'Engine brake', 'They are equal' }, a = 2 },
        { q = 'How many passengers may ride on a standard motorcycle?', c = { 'None', 'One, on a proper seat with footrests', 'Two', 'As many as fit' }, a = 2 },
        { q = 'Before changing lanes on a motorcycle you should:', c = { 'Honk', 'Speed up', 'Check mirrors and look over your shoulder', 'Flash your lights' }, a = 3 },
    },
    cdl = {
        { q = 'Before every trip, a commercial driver must:', c = { 'Fill the tank', 'Do a pre-trip inspection', 'Call dispatch', 'Wash the truck' }, a = 2 },
        { q = 'Large trucks need more distance to stop because:', c = { 'They are heavier', 'They have fewer brakes', 'Truck drivers react slower', 'They don\'t' }, a = 1 },
        { q = 'What is a "No-Zone"?', c = { 'A no-parking area', 'A truck\'s blind spots', 'A toll-free road', 'A weigh station' }, a = 2 },
        { q = 'When going down a long, steep hill you should:', c = { 'Shift to neutral', 'Ride the brakes all the way', 'Use a lower gear', 'Speed up to get it over with' }, a = 3 },
        { q = 'Your cargo must be:', c = { 'Covered in plastic', 'Secured so it can\'t shift or fall', 'Under 1 ton', 'Inspected by police' }, a = 2 },
    },
    hazmat = {
        { q = 'Vehicles carrying hazardous materials must display:', c = { 'Flashing lights', 'The correct placards', 'A company logo', 'Nothing' }, a = 2 },
        { q = 'At a railroad crossing, a HazMat vehicle must:', c = { 'Cross quickly', 'Stop, look and listen before crossing', 'Honk twice', 'Follow the car in front' }, a = 2 },
        { q = 'Who is responsible for checking the shipping papers are with the load?', c = { 'The police', 'The driver', 'The customer', 'Nobody' }, a = 2 },
        { q = 'If your HazMat load is leaking you should:', c = { 'Keep driving to the destination', 'Stop, keep people away and call for help', 'Wash it off', 'Open all the doors' }, a = 2 },
        { q = 'Smoking near a HazMat load is:', c = { 'Fine with the windows down', 'Allowed after 10 minutes', 'Never allowed', 'Allowed at night' }, a = 3 },
    },
    weapon = {
        { q = 'The first rule of firearm safety is:', c = { 'Always treat a gun as if it is loaded', 'Clean it weekly', 'Keep it in your glovebox', 'Buy the biggest caliber' }, a = 1 },
        { q = 'Where should your finger be until you are ready to fire?', c = { 'On the trigger', 'Off the trigger, along the frame', 'On the safety', 'In your pocket' }, a = 2 },
        { q = 'Before firing you must be sure of:', c = { 'The weather', 'Your target and what is behind it', 'Your ammo brand', 'Nothing' }, a = 2 },
        { q = 'When you are stopped by police while carrying, you should:', c = { 'Reach for your weapon to show it', 'Tell the officer and keep your hands visible', 'Drive away', 'Say nothing' }, a = 2 },
        { q = 'Firearms at home should be stored:', c = { 'Loaded on a table', 'Locked and out of reach of others', 'In the car', 'Under the pillow' }, a = 2 },
    },
    boat = {
        { q = 'On the water, who must give way when two boats approach head-on?', c = { 'The bigger boat', 'Both turn to their right (starboard)', 'Both turn left', 'Whoever is slower' }, a = 2 },
        { q = 'How many life jackets must be on board?', c = { 'One', 'One per person', 'Two', 'None near shore' }, a = 2 },
        { q = 'Near swimmers and docks you should:', c = { 'Slow down to no-wake speed', 'Speed up', 'Sound your horn', 'Turn off the engine' }, a = 1 },
        { q = 'Operating a boat after drinking is:', c = { 'Allowed', 'Illegal, same as driving', 'Allowed at night', 'Allowed on lakes' }, a = 2 },
        { q = 'A red buoy marks:', c = { 'A swimming area', 'One side of a channel', 'Fuel', 'A shipwreck' }, a = 2 },
    },
    pilot = {
        { q = 'Before every flight a pilot must:', c = { 'File a complaint', 'Do a pre-flight check', 'Refuel to half', 'Call the tower twice' }, a = 2 },
        { q = 'Restricted airspace (like Fort Zancudo) may be entered:', c = { 'Any time', 'Only with clearance', 'At night', 'Above 1,000 ft' }, a = 2 },
        { q = 'Helicopters may land on:', c = { 'Any road', 'Approved helipads or with permission', 'Rooftops anywhere', 'Highways' }, a = 2 },
        { q = 'If your engine fails in a plane you should:', c = { 'Jump out', 'Keep airspeed up and glide to a safe landing area', 'Climb steeply', 'Turn off the radio' }, a = 2 },
        { q = 'Minimum safe altitude over a crowded city area is roughly:', c = { '100 ft', '1,000 ft above the highest obstacle', 'Ground level', 'Anything goes' }, a = 2 },
    },
}
