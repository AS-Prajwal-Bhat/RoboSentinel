% ====================================================================
% ROBOSENTINEL - IMPROVED FACE RECOGNITION (v2.0)
% ====================================================================
% IMPROVEMENTS:
% - Multiple feature extraction methods (HOG + LBP)
% - Better preprocessing and normalization
% - Ensemble matching for higher accuracy
% - Adaptive thresholding based on lighting
% - Face quality scoring
% ====================================================================

classdef RoboSentinel < handle
    properties
        camURL              
        knownFaces          % Cell array of face features
        knownNames          
        faceDetector        
        alertCallback       
        processInterval     
        isRunning           
        enhanceImage        
        
        % Detection tracking
        currentKnownFaces   
        currentUnknownFaces 
        
        % NEW: Advanced features
        useHOG              % Use HOG features
        useLBP              % Use LBP features
        minFaceQuality      % Minimum quality threshold
    end
    
    methods
        function obj = RoboSentinel(esp32_ip, varargin)
            p = inputParser;
            addRequired(p, 'esp32_ip', @ischar);
            addParameter(p, 'ProcessInterval', 0.3, @isnumeric);
            addParameter(p, 'EnhanceImage', true, @islogical);
            addParameter(p, 'UseHOG', true, @islogical);
            addParameter(p, 'UseLBP', true, @islogical);
            parse(p, esp32_ip, varargin{:});
            
            obj.camURL = ['http://' p.Results.esp32_ip ':81/stream'];
            obj.processInterval = p.Results.ProcessInterval;
            obj.enhanceImage = p.Results.EnhanceImage;
            obj.useHOG = p.Results.UseHOG;
            obj.useLBP = p.Results.UseLBP;
            obj.isRunning = false;
            obj.minFaceQuality = 0.3;
            
            % Enhanced face detector settings
            obj.faceDetector = vision.CascadeObjectDetector('ClassificationModel', 'FrontalFaceCART');
            obj.faceDetector.MinSize = [80 80];
            obj.faceDetector.MaxSize = [400 400];
            obj.faceDetector.MergeThreshold = 6;
            obj.faceDetector.ScaleFactor = 1.1;
            
            obj.knownFaces = {};
            obj.knownNames = {};
            obj.currentKnownFaces = {};
            obj.currentUnknownFaces = 0;
            
            fprintf('RoboSentinel v2.0 initialized\n');
            fprintf('Features: HOG=%d, LBP=%d\n', obj.useHOG, obj.useLBP);
        end
        
        function quality = assessFaceQuality(obj, faceImg)
            % Assess quality of detected face (blur, lighting, size)
            
            % Check size
            [h, w] = size(faceImg);
            if h < 60 || w < 60
                quality = 0;
                return;
            end
            
            % Compute sharpness using Laplacian variance
            lap = fspecial('laplacian');
            laplacian = imfilter(double(faceImg), lap, 'replicate');
            sharpness = std2(laplacian);
            
            % Normalize sharpness (typical range 5-50 for decent faces)
            sharpScore = min(sharpness / 30, 1.0);
            
            % Check lighting variance
            lightScore = std2(double(faceImg)) / 128;
            lightScore = min(lightScore, 1.0);
            
            % Combined quality
            quality = (sharpScore * 0.6 + lightScore * 0.4);
        end
        
        function features = extractHOGFeatures(obj, faceImg)
            % Extract HOG (Histogram of Oriented Gradients) features
            try
                % Resize to standard size
                faceImg = imresize(faceImg, [128 128]);
                
                % Extract HOG features with optimal parameters
                features = extractHOGFeatures(faceImg, 'CellSize', [8 8], ...
                    'BlockSize', [2 2], 'NumBins', 9);
                
                % Normalize
                features = features / (norm(features) + 1e-6);
            catch
                features = [];
            end
        end
        
        function features = extractLBPFeatures(obj, faceImg)
            % Extract LBP (Local Binary Pattern) features
            try
                % Resize to standard size
                faceImg = imresize(faceImg, [100 100]);
                
                % Extract LBP features
                lbpFeatures = extractLBPFeatures(faceImg, 'Upright', false);
                
                % Normalize
                features = lbpFeatures / (sum(lbpFeatures) + 1e-6);
            catch
                features = [];
            end
        end
        
        function features = extractPixelFeatures(obj, faceImg)
            % Extract normalized pixel features as fallback
            
            faceImg = imresize(faceImg, [64 64]);
            faceImg = double(faceImg);
            
            % Normalize
            faceImg = (faceImg - mean(faceImg(:))) / (std(faceImg(:)) + 1e-6);
            features = faceImg(:)';
        end
        
        function addKnownFace(obj, imagePath, personName)
            try
                img = imread(imagePath);
                if size(img, 3) == 3
                    grayImg = rgb2gray(img);
                else
                    grayImg = img;
                end
                
                % Detect face
                bbox = obj.faceDetector(grayImg);
                
                if isempty(bbox)
                    warning('No face detected in %s', imagePath);
                    return;
                end
                
                % Use largest face
                if size(bbox, 1) > 1
                    areas = bbox(:,3) .* bbox(:,4);
                    [~, idx] = max(areas);
                    bbox = bbox(idx, :);
                end
                
                face = imcrop(grayImg, bbox);
                
                % Check quality
                quality = obj.assessFaceQuality(face);
                if quality < obj.minFaceQuality
                    warning('Low quality face image (%.2f). Try better lighting/focus.', quality);
                end
                
                % Enhance face
                face = obj.enhanceFaceForRecognition(face);
                
                % Extract multiple features
                faceFeatures = struct();
                
                if obj.useHOG
                    faceFeatures.hog = obj.extractHOGFeatures(face);
                end
                
                if obj.useLBP
                    faceFeatures.lbp = obj.extractLBPFeatures(face);
                end
                
                faceFeatures.pixel = obj.extractPixelFeatures(face);
                faceFeatures.quality = quality;
                
                % Store
                obj.knownFaces{end+1} = faceFeatures;
                obj.knownNames{end+1} = personName;
                
                fprintf('✓ Added %s (Quality: %.2f)\n', personName, quality);
                
            catch ME
                warning('Error adding face: %s', ME.message);
            end
        end
        
        function enhanced = enhanceFaceForRecognition(obj, face)
            % Enhanced preprocessing for better recognition
            
            % Resize to standard size
            enhanced = imresize(face, [100 100]);
            
            % Apply CLAHE for better contrast
            enhanced = adapthisteq(enhanced, 'ClipLimit', 0.015, 'Distribution', 'uniform');
            
            % Gaussian smoothing to reduce noise
            enhanced = imgaussfilt(enhanced, 0.8);
            
            % Histogram equalization
            enhanced = histeq(enhanced);
        end
        
        function img = captureFrame(obj)
            try
                snapshotURL = strrep(obj.camURL, ':81/stream', '/capture');
                img = webread(snapshotURL, weboptions('Timeout', 5));
            catch
                try
                    img = webread(obj.camURL, weboptions('Timeout', 5));
                catch ME
                    error('Cannot connect to ESP32-CAM');
                end
            end
        end
        
        function enhanced = enhanceFrame(obj, img)
            if ~obj.enhanceImage
                enhanced = img;
                return;
            end
            
            if size(img, 3) == 3
                enhanced = rgb2gray(img);
            else
                enhanced = img;
            end
            
            enhanced = adapthisteq(enhanced, 'ClipLimit', 0.02);
        end
        
        function similarity = computeFeatureSimilarity(obj, feat1, feat2)
            % Compute similarity between two feature vectors
            
            % Cosine similarity
            similarity = dot(feat1, feat2) / (norm(feat1) * norm(feat2) + 1e-6);
            
            % Normalize to [0, 1]
            similarity = (similarity + 1) / 2;
        end
        
        function [isKnown, name, confidence] = recognizeFace(obj, faceImg)
            % IMPROVED: Multi-feature ensemble recognition
            
            if isempty(obj.knownFaces)
                isKnown = false;
                name = 'Unknown';
                confidence = 0;
                return;
            end
            
            % Check quality
            quality = obj.assessFaceQuality(faceImg);
            if quality < obj.minFaceQuality * 0.8
                isKnown = false;
                name = 'Unknown';
                confidence = 0;
                fprintf('[REJECT] Poor face quality: %.2f\n', quality);
                return;
            end
            
            % Enhance face
            faceImg = obj.enhanceFaceForRecognition(faceImg);
            
            % Extract features from detected face
            testFeatures = struct();
            
            if obj.useHOG
                testFeatures.hog = obj.extractHOGFeatures(faceImg);
            end
            
            if obj.useLBP
                testFeatures.lbp = obj.extractLBPFeatures(faceImg);
            end
            
            testFeatures.pixel = obj.extractPixelFeatures(faceImg);
            
            % Compare with all known faces
            numKnown = length(obj.knownFaces);
            scores = zeros(numKnown, 3);  % HOG, LBP, Pixel
            
            for i = 1:numKnown
                knownFeat = obj.knownFaces{i};
                
                % HOG similarity
                if obj.useHOG && ~isempty(testFeatures.hog) && ~isempty(knownFeat.hog)
                    scores(i, 1) = obj.computeFeatureSimilarity(testFeatures.hog, knownFeat.hog);
                end
                
                % LBP similarity
                if obj.useLBP && ~isempty(testFeatures.lbp) && ~isempty(knownFeat.lbp)
                    scores(i, 2) = obj.computeFeatureSimilarity(testFeatures.lbp, knownFeat.lbp);
                end
                
                % Pixel similarity
                if ~isempty(testFeatures.pixel) && ~isempty(knownFeat.pixel)
                    scores(i, 3) = obj.computeFeatureSimilarity(testFeatures.pixel, knownFeat.pixel);
                end
            end
            
            % Ensemble score (weighted average)
            weights = [0.4, 0.4, 0.2];  % HOG and LBP more important
            ensembleScores = scores * weights';
            
            % Find best match
            [maxScore, bestMatch] = max(ensembleScores);
            
            % Adaptive threshold based on number of known faces
            baseThreshold = 0.55;
            if numKnown > 3
                baseThreshold = 0.60;
            end
            
            % Check if match is strong enough
            if maxScore >= baseThreshold
                % Check if significantly better than second best
                ensembleScores(bestMatch) = -inf;
                secondBest = max(ensembleScores);
                margin = maxScore - secondBest;
                
                if margin > 0.08 || secondBest < 0.45
                    isKnown = true;
                    name = obj.knownNames{bestMatch};
                    confidence = maxScore;
                    
                    fprintf('[MATCH] %s | Score: %.3f (2nd: %.3f, Δ=%.3f)\n', ...
                        name, maxScore, secondBest, margin);
                else
                    isKnown = false;
                    name = 'Unknown';
                    confidence = 0;
                    fprintf('[REJECT] Ambiguous | Best: %.3f, 2nd: %.3f, Δ=%.3f\n', ...
                        maxScore, secondBest, margin);
                end
            else
                isKnown = false;
                name = 'Unknown';
                confidence = 0;
                fprintf('[REJECT] Low score: %.3f < %.3f\n', maxScore, baseThreshold);
            end
        end
        
        function start(obj, displayVideo)
            if nargin < 2
                displayVideo = true;
            end
            
            obj.isRunning = true;
            
            if displayVideo
                fig = figure('Name', 'RoboSentinel v2.0 - Live Feed', ...
                    'NumberTitle', 'off', ...
                    'Position', [100 100 800 600], ...
                    'CloseRequestFcn', @(src,evt)obj.stop());
            end
            
            fprintf('\n=== RoboSentinel v2.0 Started ===\n');
            fprintf('Known faces: %d\n', length(obj.knownNames));
            fprintf('Press Ctrl+C or close window to stop\n\n');
            
            lastProcessTime = tic;
            frameCount = 0;
            fpsTime = tic;
            fps = 0;
            
            while obj.isRunning
                try
                    img = obj.captureFrame();
                    frameCount = frameCount + 1;
                    
                    if toc(fpsTime) >= 1
                        fps = frameCount / toc(fpsTime);
                        frameCount = 0;
                        fpsTime = tic;
                    end
                    
                    if toc(lastProcessTime) >= obj.processInterval
                        obj.currentKnownFaces = {};
                        obj.currentUnknownFaces = 0;
                        
                        enhanced = obj.enhanceFrame(img);
                        bbox = obj.faceDetector(enhanced);
                        
                        for i = 1:size(bbox, 1)
                            face = imcrop(enhanced, bbox(i,:));
                            [isKnown, name, conf] = obj.recognizeFace(face);
                            
                            if isKnown
                                if ~ismember(name, obj.currentKnownFaces)
                                    obj.currentKnownFaces{end+1} = name;
                                end
                            else
                                obj.currentUnknownFaces = obj.currentUnknownFaces + 1;
                                
                                if ~isempty(obj.alertCallback)
                                    obj.alertCallback(img, bbox(i,:));
                                end
                            end
                        end
                        
                        lastProcessTime = tic;
                    end
                    
                    if displayVideo && ishandle(fig)
                        imgDisplay = img;
                        if size(img, 3) == 1
                            imgDisplay = cat(3, img, img, img);
                        end
                        
                        if exist('bbox', 'var') && ~isempty(bbox)
                            for i = 1:size(bbox, 1)
                                face = imcrop(obj.enhanceFrame(img), bbox(i,:));
                                [isKnown, name, conf] = obj.recognizeFace(face);
                                
                                if isKnown
                                    imgDisplay = insertShape(imgDisplay, 'Rectangle', bbox(i,:), ...
                                        'Color', 'green', 'LineWidth', 4);
                                    label = sprintf('%s (%.0f%%)', name, conf*100);
                                    imgDisplay = insertText(imgDisplay, [bbox(i,1) bbox(i,2)-10], ...
                                        label, 'FontSize', 16, 'BoxColor', 'green', ...
                                        'BoxOpacity', 0.8, 'TextColor', 'white');
                                else
                                    imgDisplay = insertShape(imgDisplay, 'Rectangle', bbox(i,:), ...
                                        'Color', 'red', 'LineWidth', 4);
                                    imgDisplay = insertText(imgDisplay, [bbox(i,1) bbox(i,2)-10], ...
                                        'UNKNOWN', 'FontSize', 16, 'BoxColor', 'red', ...
                                        'BoxOpacity', 0.8, 'TextColor', 'white');
                                end
                            end
                        end
                        
                        imgDisplay = insertText(imgDisplay, [10 10], ...
                            sprintf('FPS: %.1f', fps), ...
                            'FontSize', 18, 'BoxColor', 'black', ...
                            'BoxOpacity', 0.7, 'TextColor', 'lime');
                        
                        statsText = sprintf('Known: %d | Unknown: %d | DB: %d', ...
                            length(obj.currentKnownFaces), obj.currentUnknownFaces, ...
                            length(obj.knownNames));
                        imgDisplay = insertText(imgDisplay, [10 40], statsText, ...
                            'FontSize', 14, 'BoxColor', 'black', ...
                            'BoxOpacity', 0.7, 'TextColor', 'cyan');
                        
                        imshow(imgDisplay);
                        drawnow;
                    end
                    
                catch ME
                    if strcmp(ME.identifier, 'MATLAB:class:InvalidHandle')
                        obj.stop();
                    else
                        warning('Error: %s', ME.message);
                    end
                end
            end
            
            fprintf('\n=== RoboSentinel Stopped ===\n');
        end
        
        function stop(obj)
            obj.isRunning = false;
        end
        
        function setAlertCallback(obj, callback)
            obj.alertCallback = callback;
        end
    end
end