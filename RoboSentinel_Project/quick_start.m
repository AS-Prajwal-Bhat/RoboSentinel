%% ====================================================================
%% ROBOSENTINEL v2.0 - QUICK START (IMPROVED DETECTION)
%% ====================================================================

clear; clc; close all;

fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║      ROBOSENTINEL v2.0 - FACE DETECTION SYSTEM            ║\n');
fprintf('║      Improved Recognition with HOG + LBP Features          ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n\n');

%% ====================================================================
%% STEP 1: CONFIGURATION
%% ====================================================================
fprintf('STEP 1: Configuration\n');
fprintf('─────────────────────\n');

default_cam_ip = '192.168.1.100';

fprintf('Enter ESP32-CAM IP address\n');
fprintf('(Press Enter for default: %s): ', default_cam_ip);
user_cam_ip = input('', 's');

if isempty(user_cam_ip)
    ESP32_CAM_IP = default_cam_ip;
else
    ESP32_CAM_IP = user_cam_ip;
end

fprintf('\n✓ Using ESP32-CAM IP: %s\n\n', ESP32_CAM_IP);

%% ====================================================================
%% STEP 2: TEST CONNECTION
%% ====================================================================
fprintf('STEP 2: Testing Connection\n');
fprintf('───────────────────────────\n');

try
    testURL = ['http://' ESP32_CAM_IP '/capture'];
    fprintf('Testing: %s\n', testURL);
    testImg = webread(testURL, weboptions('Timeout', 8));
    fprintf('✓ Connection successful!\n');
    fprintf('✓ Image size: %dx%d\n\n', size(testImg, 2), size(testImg, 1));
catch ME
    fprintf('✗ Connection FAILED!\n');
    fprintf('  Error: %s\n\n', ME.message);
    fprintf('Troubleshooting:\n');
    fprintf('  1. Check ESP32-CAM power (needs 5V, 2A+)\n');
    fprintf('  2. Verify IP address matches ESP32-CAM\n');
    fprintf('  3. Ensure both on same WiFi network\n');
    fprintf('  4. Try ping: ping %s\n', ESP32_CAM_IP);
    fprintf('  5. Check ESP32 serial monitor for errors\n\n');
    return;
end

%% ====================================================================
%% STEP 3: CREATE SYSTEM
%% ====================================================================
fprintf('STEP 3: Initializing System\n');
fprintf('────────────────────────────\n');

try
    bridge = RoboSentinelWebBridge(ESP32_CAM_IP, 'ProcessInterval', 0.4);
    fprintf('✓ RoboSentinel v2.0 initialized!\n');
    fprintf('✓ Detection features: HOG + LBP + Pixel\n\n');
catch ME
    fprintf('✗ Initialization failed: %s\n', ME.message);
    fprintf('  Make sure RoboSentinel.m and RoboSentinelWebBridge.m exist\n\n');
    return;
end

%% ====================================================================
%% STEP 4: ADD KNOWN FACES (CRITICAL FOR RECOGNITION)
%% ====================================================================
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║  STEP 4: Add Known Faces (IMPORTANT!)                     ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n\n');

fprintf('⚠️  WARNING: Without known faces, everyone will be "Unknown"!\n\n');
fprintf('Options:\n');
fprintf('  1 = Add from image files (recommended)\n');
fprintf('  2 = Capture from ESP32-CAM live\n');
fprintf('  3 = Skip (test detection only)\n\n');

choice = input('Select option (1/2/3): ');

switch choice
    case 1
        %% Add from files
        fprintf('\n--- ADD FROM IMAGE FILES ---\n');
        fprintf('Tips for best results:\n');
        fprintf('  • Use well-lit photos\n');
        fprintf('  • Face should be clearly visible\n');
        fprintf('  • Frontal view works best\n');
        fprintf('  • Avoid sunglasses/hats\n\n');
        
        numPeople = input('How many people to add? ');
        
        for i = 1:numPeople
            fprintf('\n┌─ Person %d of %d ─────────────────┐\n', i, numPeople);
            
            while true
                imagePath = input('│ Image file path: ', 's');
                if exist(imagePath, 'file')
                    break;
                else
                    fprintf('│ ✗ File not found. Try again.\n');
                end
            end
            
            personName = input('│ Person name: ', 's');
            
            try
                % Show image preview
                img = imread(imagePath);
                figure('Name', 'Preview');
                imshow(img);
                title(sprintf('Adding: %s', personName));
                pause(0.5);
                close(gcf);
                
                bridge.addKnownFace(imagePath, personName);
                fprintf('└─ ✓ Added %s successfully!\n', personName);
            catch ME
                fprintf('└─ ✗ Error: %s\n', ME.message);
            end
        end
        
    case 2
        %% Capture from camera
        fprintf('\n--- CAPTURE FROM CAMERA ---\n');
        
        fprintf('Testing camera...\n');
        try
            testImg = bridge.sentinel.captureFrame();
            fprintf('✓ Camera working!\n\n');
            
            % Show test frame
            figure('Name', 'Camera Test');
            imshow(testImg);
            title('Camera Feed OK');
            pause(1);
            close(gcf);
            
        catch ME
            fprintf('✗ Camera error: %s\n', ME.message);
            return;
        end
        
        numPeople = input('How many people to add? ');
        
        fprintf('\nCapture Tips:\n');
        fprintf('  • Position face centered\n');
        fprintf('  • Ensure good lighting\n');
        fprintf('  • Look at camera\n');
        fprintf('  • Stay still when capturing\n\n');
        
        for i = 1:numPeople
            fprintf('\n┌─ Person %d of %d ─────────────────┐\n', i, numPeople);
            personName = input('│ Person name: ', 's');
            
            fprintf('│ Position %s in front of camera\n', personName);
            fprintf('│ Capturing in: ');
            for j = 3:-1:1
                fprintf('%d... ', j);
                pause(1);
            end
            fprintf('NOW!\n');
            
            % Capture
            img = bridge.sentinel.captureFrame();
            
            % Show captured image
            fig = figure('Name', sprintf('Captured: %s', personName));
            imshow(img);
            title(sprintf('Is this good for %s?', personName));
            
            useThis = input('│ Use this image? (y/n): ', 's');
            close(fig);
            
            if strcmpi(useThis, 'y')
                filename = sprintf('known_%s_%d.jpg', strrep(personName, ' ', '_'), i);
                imwrite(img, filename);
                
                bridge.addKnownFace(filename, personName);
                fprintf('└─ ✓ Added %s!\n', personName);
            else
                fprintf('└─ Skipped. Retrying...\n');
                i = i - 1;
            end
        end
        
    case 3
        fprintf('\n⚠️  SKIPPING face database!\n');
        fprintf('   All faces will be detected as UNKNOWN.\n');
        fprintf('   This is only useful for testing detection.\n\n');
        
    otherwise
        fprintf('Invalid option. Skipping.\n\n');
end

fprintf('\n');
fprintf('════════════════════════════════════════════════════════════\n');
fprintf('Known Faces Database: %d people\n', length(bridge.sentinel.knownNames));

if ~isempty(bridge.sentinel.knownNames)
    fprintf('Registered:\n');
    for i = 1:length(bridge.sentinel.knownNames)
        fprintf('  %d. %s\n', i, bridge.sentinel.knownNames{i});
    end
end
fprintf('════════════════════════════════════════════════════════════\n\n');

%% ====================================================================
%% STEP 5: WEB INTERFACE INSTRUCTIONS
%% ====================================================================
fprintf('STEP 5: Web Dashboard Setup\n');
fprintf('────────────────────────────\n');
fprintf('To view detection results on your HTML dashboard:\n\n');
fprintf('1️⃣  Status data will be written to: sentinel_data/status.json\n');
fprintf('2️⃣  Your HTML file should read this JSON file\n');
fprintf('3️⃣  Start a local web server:\n');
fprintf('    - Open terminal in this folder\n');
fprintf('    - Run: python -m http.server 3000\n');
fprintf('    - Or: python3 -m http.server 3000\n');
fprintf('4️⃣  Open browser: http://localhost:3000/your_page.html\n\n');

fprintf('JSON data structure:\n');
fprintf('{\n');
fprintf('  "currentKnownFaces": 2,\n');
fprintf('  "currentUnknownFaces": 0,\n');
fprintf('  "knownFaceNames": ["Alice", "Bob"],\n');
fprintf('  "alert": false,\n');
fprintf('  "message": "✓ Recognized: Alice, Bob",\n');
fprintf('  "history": [...]\n');
fprintf('}\n\n');

%% ====================================================================
%% STEP 6: START DETECTION
%% ====================================================================
fprintf('STEP 6: Start Face Detection\n');
fprintf('─────────────────────────────\n');

startNow = input('Start detection system now? (y/n): ', 's');

if strcmpi(startNow, 'y')
    fprintf('\n');
    fprintf('╔════════════════════════════════════════════════════════════╗\n');
    fprintf('║            STARTING DETECTION SYSTEM...                   ║\n');
    fprintf('╚════════════════════════════════════════════════════════════╝\n\n');
    
    fprintf('System Info:\n');
    fprintf('  📹 Camera: %s\n', ESP32_CAM_IP);
    fprintf('  👥 Known: %d people\n', length(bridge.sentinel.knownNames));
    fprintf('  📊 Data: sentinel_data/status.json\n');
    fprintf('  ⚙️  Features: HOG + LBP + Pixel matching\n\n');
    
    fprintf('Controls:\n');
    fprintf('  • Video window shows live detection\n');
    fprintf('  • Green box = Recognized person (with name)\n');
    fprintf('  • Red box = Unknown person (alert triggered)\n');
    fprintf('  • Close window or Ctrl+C to stop\n\n');
    
    fprintf('Starting in 3 seconds...\n');
    pause(3);
    
    try
        bridge.start(true);
    catch ME
        fprintf('\n✗ Detection error: %s\n', ME.message);
    end
    
else
    fprintf('\n📋 System ready but not started.\n');
    fprintf('   To start manually:\n');
    fprintf('   >> bridge.start(true);\n\n');
end

%% ====================================================================
%% HELPFUL COMMANDS
%% ====================================================================
fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║              USEFUL COMMANDS                               ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n');
fprintf('bridge.start(true)                   - Start with video\n');
fprintf('bridge.stop()                        - Stop detection\n');
fprintf('bridge.addKnownFace(path, name)      - Add more faces\n');
fprintf('bridge.sentinel.captureFrame()       - Test camera\n');
fprintf('bridge.sentinel.minFaceQuality=0.2   - Lower quality threshold\n\n');

fprintf('Detection not working? Try:\n');
fprintf('1. Add more photos of each person (different angles)\n');
fprintf('2. Use better lit photos\n');
fprintf('3. Check camera focus\n');
fprintf('4. Lower threshold: bridge.sentinel.minFaceQuality = 0.2\n\n');

fprintf('✅ Setup complete!\n\n');