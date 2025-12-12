%% ROBOSENTINEL COMPLETE SETUP
clear; clc;

%% 1. CONFIGURATION
ESP32_CAM_IP = '192.168.1.100';  % <<<< CHANGE THIS
MATLAB_PORT = 8080;

fprintf('=== RoboSentinel Setup ===\n\n');

%% 2. CREATE BRIDGE
bridge = RoboSentinelWebBridge(ESP32_CAM_IP, 'Port', MATLAB_PORT);

%% 3. ADD KNOWN FACES
choice = input('Add known faces? (y/n): ', 's');

if strcmpi(choice, 'y')
    numPeople = input('How many people? ');
    
    for i = 1:numPeople
        fprintf('\n--- Person %d ---\n', i);
        
        % Option 1: From file
        fprintf('1. Load from image file\n');
        fprintf('2. Capture from ESP32-CAM\n');
        opt = input('Select option: ');
        
        if opt == 1
            imagePath = input('Image path: ', 's');
            personName = input('Person name: ', 's');
            bridge.addKnownFace(imagePath, personName);
            
        elseif opt == 2
            personName = input('Person name: ', 's');
            fprintf('Position %s in front of camera...\n', personName);
            pause(3);
            
            img = bridge.sentinel.captureFrame();
            filename = sprintf('known_%s.jpg', personName);
            imwrite(img, filename);
            bridge.addKnownFace(filename, personName);
        end
    end
end

%% 4. START SYSTEM
fprintf('\n=== Starting System ===\n');
fprintf('MATLAB Web Server: http://localhost:%d\n', MATLAB_PORT);
fprintf('Open your HTML dashboard in browser now!\n');
fprintf('Close MATLAB window or press Ctrl+C to stop\n\n');

pause(2);
bridge.start(true);  % true = show video window