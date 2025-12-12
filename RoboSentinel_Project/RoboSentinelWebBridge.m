% ====================================================================
% ROBOSENTINEL WEB BRIDGE v2.0 - IMPROVED
% ====================================================================

classdef RoboSentinelWebBridge < handle
    properties
        sentinel            
        latestDetection    
        detectionHistory   
        alertActive        
        updateTimer        
        unknownFaceCount   
        knownFaceNames     
        lastAlertTime      % Prevent alert spam
    end
    
    methods
        function obj = RoboSentinelWebBridge(esp32_cam_ip, varargin)
            p = inputParser;
            addRequired(p, 'esp32_cam_ip', @ischar);
            addParameter(p, 'ProcessInterval', 0.5, @isnumeric);
            parse(p, esp32_cam_ip, varargin{:});
            
            obj.latestDetection = struct('status', 'idle', ...
                                        'timestamp', datestr(now, 'HH:MM:SS'), ...
                                        'faces', [], ...
                                        'alert', false);
            obj.detectionHistory = {};
            obj.alertActive = false;
            obj.unknownFaceCount = 0;
            obj.knownFaceNames = {};
            obj.lastAlertTime = 0;
            
            obj.sentinel = RoboSentinel(esp32_cam_ip, ...
                'ProcessInterval', p.Results.ProcessInterval, ...
                'UseHOG', true, ...
                'UseLBP', true);
            
            obj.sentinel.setAlertCallback(@(img, bbox) obj.handleAlert(img, bbox));
            
            fprintf('=== RoboSentinel Web Bridge v2.0 ===\n');
            fprintf('ESP32-CAM IP: %s\n', esp32_cam_ip);
        end
        
        function addKnownFace(obj, imagePath, personName)
            obj.sentinel.addKnownFace(imagePath, personName);
        end
        
        function handleAlert(obj, img, bbox)
            % Prevent alert spam (minimum 3 seconds between alerts)
            if (now - obj.lastAlertTime) * 86400 < 3
                return;
            end
            
            obj.alertActive = true;
            obj.unknownFaceCount = obj.unknownFaceCount + 1;
            obj.lastAlertTime = now;
            
            obj.latestDetection.status = 'alert';
            obj.latestDetection.timestamp = datestr(now, 'HH:MM:SS');
            obj.latestDetection.alert = true;
            obj.latestDetection.message = '⚠️ UNKNOWN FACE DETECTED';
            
            obj.addToHistory('Unknown Person', 'ALERT');
            
            fprintf('[ALERT] Unknown face detected at %s\n', obj.latestDetection.timestamp);
            
            obj.updateStatusFile();
            
            % Auto-clear alert after 8 seconds
            t = timer('StartDelay', 8, ...
                     'TimerFcn', @(~,~) obj.clearAlert(), ...
                     'ExecutionMode', 'singleShot');
            start(t);
        end
        
        function clearAlert(obj)
            obj.alertActive = false;
            obj.latestDetection.alert = false;
            obj.updateStatusFile();
            fprintf('[INFO] Alert cleared\n');
        end
        
        function addToHistory(obj, name, status)
            entry = struct('name', name, ...
                          'status', status, ...
                          'time', datestr(now, 'HH:MM:SS'));
            obj.detectionHistory{end+1} = entry;
            if length(obj.detectionHistory) > 15
                obj.detectionHistory(1) = [];
            end
        end
        
        function startWebServer(obj)
            if ~exist('sentinel_data', 'dir')
                mkdir('sentinel_data');
            end
            
            fprintf('✓ File-based server initialized\n');
            fprintf('✓ Data folder: sentinel_data/\n');
            fprintf('✓ Status file: sentinel_data/status.json\n\n');
            
            obj.updateStatusFile();
            
            obj.updateTimer = timer('Period', 0.3, ...
                     'ExecutionMode', 'fixedRate', ...
                     'TimerFcn', @(~,~) obj.updateStatusFile());
            start(obj.updateTimer);
        end
        
        function updateStatusFile(obj)
            data = struct();
            data.status = 'active';
            data.timestamp = datestr(now, 'HH:MM:SS dd-mmm-yyyy');
            data.alert = obj.alertActive;
            
            % Current detections
            data.currentKnownFaces = length(obj.sentinel.currentKnownFaces);
            data.currentUnknownFaces = obj.sentinel.currentUnknownFaces;
            data.knownFaceNames = obj.sentinel.currentKnownFaces;
            
            % Build status message
            if obj.alertActive
                data.message = sprintf('⚠️ UNKNOWN FACE DETECTED! (%d unknown faces)', ...
                    obj.sentinel.currentUnknownFaces);
                data.alertType = 'danger';
                data.alertSound = true;
            else
                if data.currentKnownFaces > 0
                    namesStr = strjoin(obj.sentinel.currentKnownFaces, ', ');
                    data.message = sprintf('✓ Recognized: %s', namesStr);
                    data.alertType = 'success';
                    
                    % Add to history when new person detected
                    for i = 1:length(obj.sentinel.currentKnownFaces)
                        personName = obj.sentinel.currentKnownFaces{i};
                        % Check if recently added to history
                        recentlyAdded = false;
                        if ~isempty(obj.detectionHistory)
                            lastEntries = obj.detectionHistory(max(1, end-5):end);
                            for j = 1:length(lastEntries)
                                if strcmp(lastEntries{j}.name, personName)
                                    recentlyAdded = true;
                                    break;
                                end
                            end
                        end
                        if ~recentlyAdded
                            obj.addToHistory(personName, 'RECOGNIZED');
                        end
                    end
                else
                    data.message = '👁️ System Active - No faces detected';
                    data.alertType = 'info';
                end
                data.alertSound = false;
            end
            
            % Database info
            data.totalKnownInDatabase = length(obj.sentinel.knownNames);
            data.knownPeopleList = obj.sentinel.knownNames;
            
            % Detection history
            data.history = obj.detectionHistory;
            
            % Performance stats
            data.detectionActive = obj.sentinel.isRunning;
            
            % Write to file
            try
                jsonStr = jsonencode(data);
                % Pretty print for debugging
                jsonStr = strrep(jsonStr, ',', ', ');
                
                fid = fopen('sentinel_data/status.json', 'w');
                fprintf(fid, '%s', jsonStr);
                fclose(fid);
            catch ME
                warning('Could not write status file: %s', ME.message);
            end
        end
        
        function start(obj, displayVideo)
            if nargin < 2
                displayVideo = true;
            end
            
            obj.startWebServer();
            
            fprintf('\n╔════════════════════════════════════════════╗\n');
            fprintf('║     ROBOSENTINEL v2.0 STARTING...         ║\n');
            fprintf('╚════════════════════════════════════════════╝\n\n');
            
            fprintf('📊 Status File: sentinel_data/status.json\n');
            fprintf('📹 Camera: ESP32-CAM\n');
            fprintf('👥 Known Faces: %d\n', length(obj.sentinel.knownNames));
            
            if ~isempty(obj.sentinel.knownNames)
                fprintf('\n   Registered people:\n');
                for i = 1:length(obj.sentinel.knownNames)
                    fprintf('   %d. %s\n', i, obj.sentinel.knownNames{i});
                end
            end
            
            fprintf('\n🌐 To view web dashboard:\n');
            fprintf('   1. Open terminal in this folder\n');
            fprintf('   2. Run: python -m http.server 3000\n');
            fprintf('   3. Visit: http://localhost:3000/your_html_file.html\n\n');
            
            fprintf('Starting in 2 seconds...\n');
            pause(2);
            
            obj.sentinel.start(displayVideo);
        end
        
        function stop(obj)
            obj.sentinel.stop();
            if ~isempty(obj.updateTimer) && isvalid(obj.updateTimer)
                stop(obj.updateTimer);
                delete(obj.updateTimer);
            end
            fprintf('System stopped.\n');
        end
    end
end