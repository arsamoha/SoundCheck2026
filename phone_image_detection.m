clear; clc;

%% Load labels
load('scan_labels.mat');
trainingData = objectDetectorTrainingData(gTruth);

%% Training set
allImgDS = imageDatastore(trainingData.imageFilename);
allBoxDS = boxLabelDatastore(table(trainingData.scan_region, 'VariableNames', {'scan_region'}));
trainDS  = combine(allImgDS, allBoxDS);

%% Validation set
valImgDS = imageDatastore(trainingData.imageFilename(25:30));
valBoxDS = boxLabelDatastore(table(trainingData.scan_region(25:30), 'VariableNames', {'scan_region'}));
valDS    = combine(valImgDS, valBoxDS);

fprintf('Training images:   %d\n', height(trainingData));
fprintf('Validation images: 6\n');

%% Apply augmentation to training data
augImgs  = cell(height(trainingData), 1);
augBoxes = cell(height(trainingData), 1);

for i = 1:height(trainingData)
    img  = imread(trainingData.imageFilename{i});
    bbox = trainingData.scan_region{i};

    augmented = augmentData({img, bbox});

    [~, name, ext] = fileparts(trainingData.imageFilename{i});
    augPath = fullfile(tempdir, ['aug_' name ext]);
    imwrite(augmented{1}, augPath);

    augImgs{i}  = augPath;
    augBoxes{i} = augmented{2};
end

augImgDS = imageDatastore(augImgs);
augBoxDS = boxLabelDatastore(table(augBoxes, 'VariableNames', {'scan_region'}));
augTrainDS = combine(augImgDS, augBoxDS);

%% Load pretrained YOLOv4
inputSize  = [416 416 3];
classNames = {'scan_region'};

detector = yolov4ObjectDetector('tiny-yolov4-coco', classNames, inputSize, ...
    'AnchorBoxes', {[81 82; 135 169; 344 319], [10 14; 23 27; 37 58]});

%% Training options
options = trainingOptions('adam', ...
    'InitialLearnRate',    1e-4, ...
    'MiniBatchSize',       2, ...
    'MaxEpochs',           150, ...
    'ValidationData',      valDS, ...
    'ValidationFrequency', 10, ...
    'Shuffle',             'every-epoch', ...
    'Verbose',             true, ...
    'Plots',               'training-progress', ...
    'CheckpointPath',      tempdir);

%% Train
fprintf('Training YOLOv4...\n');
[detector, info] = trainYOLOv4ObjectDetector(augTrainDS, detector, options);

%% Save
save('scan_region_detector_v2.mat', 'detector');
fprintf('Detector saved.\n');

%% Evaluate on validation set
results = detect(detector, valDS);
metrics = evaluateObjectDetection(results, valDS);
disp(metrics.ClassMetrics)

%% Test on a single image
img = imread('/Users/arshad.mohammad/Desktop/SoundCheck/SoundCheck2026/Data/Phone_Images/P1_20_0001.jpeg');
[bboxes, scores, labels] = detect(detector, img, 'Threshold', 0.3);

figure;
imshow(img);
if ~isempty(bboxes)
    hold on;
    rectangle('Position', bboxes(1,:), 'EdgeColor', 'g', 'LineWidth', 3);
    text(bboxes(1,1), bboxes(1,2)-10, sprintf('%.2f', scores(1)), ...
        'Color', 'g', 'FontSize', 14, 'BackgroundColor', 'k');
    fprintf('Scan region detected at [%d %d %d %d]\n', bboxes(1,:));
else
    fprintf('No scan region detected.\n');
end

%% Augmentation function
function data = augmentData(data)
    img  = data{1};
    bbox = data{2};

    if ~isa(img, 'uint8')
        img = uint8(img);
    end

    % Random horizontal flip
    if rand > 0.5
        img = fliplr(img);
        bbox(:,1) = size(img,2) - bbox(:,1) - bbox(:,3);
    end

    % Random brightness
    factor = 0.6 + rand * 0.8;
    img = uint8(min(255, double(img) * factor));

    % Clamp bbox to image bounds
    bbox(:,1) = max(bbox(:,1), 1);
    bbox(:,2) = max(bbox(:,2), 1);
    bbox(:,3) = min(bbox(:,3), size(img,2) - bbox(:,1));
    bbox(:,4) = min(bbox(:,4), size(img,1) - bbox(:,2));

    data{1} = img;
    data{2} = bbox;
end