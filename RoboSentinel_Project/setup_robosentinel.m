% ====================================================================
% ROBOSENTINEL SETUP SCRIPT
% Quick start guide for your ESP32-CAM face detection system
% ====================================================================

clear; clc;
fprintf('=== RoboSentinel Setup ===\n\n');

%% STEP 1: Configure ESP32-CAM IP Address
% Replace with your actual ESP32-CAM IP address
ESP32_IP = '192.168.1.100';  % <<< CHANGE THIS

fprintf('ESP32-CAM IP: %s\n', ESP32_IP);
fprintf('Make sure your ESP32-CAM is powered on and connected.\n\n');

%% STEP 2: Test Connection
fprintf('Testing connection to ESP32-CAM...\n');
try
    testURL = ['http://' ESP32_IP '/capture'];
    testImg = webread(testURL, weboptions('Timeout', 5));
    fprintf('✓ Connection successful!\n\n');
catch
    fprintf('✗ Connection failed! Check:\n');
    fprintf('  1. ESP32-CAM is powered on\n');
    fprintf('  2. IP address is correct\n');
    fprintf('  3. Computer and ESP32-CAM are on same network\n');
    fprintf('  4. ESP32-CAM firmware is running properly\n\n');
    return;
end

%% STEP 3: Create RoboSentinel Instance
fprintf('Initializing RoboSentinel...\n');
sentinel = RoboSentinel(ESP32_IP, 'ProcessInterval', 0.5, 'EnhanceImage', true);
fprintf('✓ RoboSentinel initialized!\n\n');

%% STEP 4: Add Known Faces
fprintf('=== Add Known Faces ===\n');
fprintf('Options:\n');
fprintf('  1. Add from image files\n');
fprintf('  2. Capture from ESP32-CAM\n');
fprintf('  3. Skip (for testing only)\n');

choice = input('Select option (1-3): ');

switch choice
    case 1
        % Add from files
        numPeople = input('How many people to add? ');
        for i = 1:numPeople
            imagePath = input(sprintf('Person %d - Image path: ', i), 's');
            personName = input(sprintf('Person %d - Name: ', i), 's');
            sentinel.addKnownFace(imagePath, personName);
        end
        
    case 2
        % Capture from camera
        numPeople = input('How many people to add? ');
        for i = 1:numPeople
            personName = input(sprintf('Person %d - Name: ', i), 's');
            fprintf('Position %s in front of camera. Press Enter when ready...\n', personName);
            pause;
            
            % Capture and save image
            img = sentinel.captureFrame();
            filename = sprintf('known_face_%d.jpg', i);
            imwrite(img, filename);
            
            % Add to database
            sentinel.addKnownFace(filename, personName);
        end
        
    case 3
        fprintf('Skipping face database setup (detection only mode)\n');
end

fprintf('\n');

%% STEP 5: Configure Alert System (Optional)
fprintf('=== Alert Configuration ===\n');
useAlert = input('Enable sound alert for unknown faces? (y/n): ', 's');

if strcmpi(useAlert, 'y')
    % Simple beep alert
    sentinel.setAlertCallback(@(img, bbox) beep);
    fprintf('✓ Sound alert enabled\n\n');
end

%% STEP 6: Start Detection
fprintf('=== Starting RoboSentinel ===\n');
fprintf('Instructions:\n');
fprintf('  - A window will open showing live feed\n');
fprintf('  - Green boxes indicate detected faces\n');
fprintf('  - Console shows recognition results\n');
fprintf('  - Close window or press Ctrl+C to stop\n\n');
fprintf('Starting in 3 seconds...\n');
pause(3);

% Start the detection system
sentinel.start(true);

fprintf('\nSetup complete! To run again, execute this script.\n');

% ====================================================================
% ADVANCED USAGE EXAMPLES
% ====================================================================

% Example 1: Run in headless mode (no video display)
% sentinel.start(false);

% Example 2: Custom alert with logging
% sentinel.setAlertCallback(@(img, bbox) logIntruder(img, bbox));

% Example 3: Adjust processing interval for performance
% sentinel.processInterval = 1.0;  % Process every 1 second (lower CPU)

% Example 4: Save snapshot on unknown face detection
% function logIntruder(img, bbox)
%     filename = sprintf('intruder_%s.jpg', datestr(now, 'yyyymmdd_HHMMSS'));
%     imwrite(img, filename);
%     fprintf('Intruder image saved: %s\n', filename);
%     beep;
% end