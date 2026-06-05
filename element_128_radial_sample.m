clear; clc;

%% INPUT
inputFolder = 'Data/Image_Scans';
fileList = dir(fullfile(inputFolder, '*.mat'));
numFiles = length(fileList);

if numFiles == 0
    error('No .mat files found.');
end

%% STORAGE
allStrips  = [];
allRatios  = zeros(128, numFiles);

%% LOOP THROUGH FILES
for f = 1:numFiles

    fprintf('Processing %d / %d\n', f, numFiles);

    fullpath = fullfile(inputFolder, fileList(f).name);
    data = load(fullpath);

    if ~isfield(data, 'imgData')
        warning('Skipping %s (no imgData)', fileList(f).name);
        continue;
    end

    imgData = double(data.imgData);

    %% ARC SAMPLING
    center = [343, -120];
    numSamples   = 128;
    profileDepth = 200;
    radius = 250;
    theta = linspace(-pi/4 + pi/2, pi/4 + pi/2, numSamples);
    arcx = center(1) + radius * cos(theta);
    arcy = center(2) + radius * sin(theta);

    ip_out = zeros(numSamples, profileDepth);

    for i = 1:numSamples
        ip = improfile(imgData, ...
            [center(1) arcx(i)], ...
            [center(2) arcy(i)], ...
            profileDepth);
        if isempty(ip), continue; end
        ip = ip(:)';
        if length(ip) < profileDepth
            ip = [ip zeros(1, profileDepth - length(ip))];
        elseif length(ip) > profileDepth
            ip = ip(1:profileDepth);
        end
        ip_out(i,:) = ip;
    end

    ip_out(isnan(ip_out)) = 0;
    colMean = mean(ip_out, 2);

    bestVal = max(colMean);
    if bestVal == 0
        ratio = zeros(size(colMean));
    else
        ratio = colMean / bestVal;
    end

    allRatios(:, f) = ratio;

    %% COLOR ASSIGNMENT
    thresh_green = 0.5;
    numElements = length(colMean);
    barColors = zeros(numElements, 3);

    for e = 1:numElements
        if ratio(e) == 0
            barColors(e,:) = [0.85 0.85 0.85];
        elseif ratio(e) >= thresh_green
            barColors(e,:) = [0.2 0.85 0.2];
        else
            barColors(e,:) = [0.9 0.1 0.1];
        end
    end

    %% COLOR STRIP
    fig = figure('Visible','off','Color','k','Position',[100 100 1200 120]);
    hold on
    for e = 1:numElements
        fill([e-0.5 e+0.5 e+0.5 e-0.5], ...
             [0 0 1 1], ...
             barColors(e,:), ...
             'EdgeColor','none')
    end
    hold off
    xlim([0 numElements+1])
    ylim([0 1])
    axis off
    set(gca, 'Position', [0 0 1 1])

    frame = getframe(fig);
    stripImg = frame.cdata;
    close(fig);

    if isempty(allStrips)
        allStrips = stripImg;
    else
        if size(stripImg,2) ~= size(allStrips,2)
            stripImg = imresize(stripImg, [size(stripImg,1), size(allStrips,2)]);
        end
        allStrips = [allStrips; stripImg];
    end

end

%% DETECT ACTIVE ELEMENTS AND CROP
meanRatioPerElement = mean(allRatios, 2);
activityThresh = 0.05;
activeElements = meanRatioPerElement >= activityThresh;

firstActive = find(activeElements, 1, 'first');
lastActive  = find(activeElements, 1, 'last');

fprintf('firstActive: %d\n', firstActive);
fprintf('lastActive: %d\n', lastActive);
fprintf('activeN: %d\n', lastActive - firstActive + 1);

stripWidth    = size(allStrips, 2);
pixPerElement = stripWidth / numSamples;

colStart = round((firstActive - 1) * pixPerElement) + 1;
colEnd   = round(lastActive * pixPerElement);
colStart = max(colStart, 1);
colEnd   = min(colEnd, stripWidth);

allStrips = allStrips(:, colStart:colEnd, :);

%% SAVE STACKED STRIP
outputFile = fullfile(inputFolder, 'overlay_raw_signals.png');
imwrite(allStrips, outputFile);
fprintf('\nSaved stacked image to:\n%s\n', outputFile);

%% ===============================================================
%% VALIDATION
%% ===============================================================

load Data/Dead_Elements/curvedDeadElements.mat
groundTruth = double(curvedDeadElements);   % [700 x 128]

%% Step 1: Normalize by MEDIAN
elementMedian = median(allRatios, 2);
elementMedian(elementMedian == 0) = 1;
allRatiosNorm = allRatios ./ elementMedian;
allRatiosNorm = min(allRatiosNorm, 1);

binaryPerf = allRatiosNorm' * 100;   % [700 x 128]

fprintf('binaryPerf size:  %d x %d\n', size(binaryPerf,1), size(binaryPerf,2));
fprintf('groundTruth size: %d x %d\n', size(groundTruth,1), size(groundTruth,2));

%% Step 2: Crop both to active element range
binaryPerfCrop     = binaryPerf(:, firstActive:lastActive);
binaryPerfCropFlip = fliplr(binaryPerfCrop);

gt_live    = (1 - groundTruth) * 100;
gt_cropped = gt_live(:, firstActive:lastActive);

fprintf('binaryPerfCrop size: %d x %d\n', size(binaryPerfCrop,1), size(binaryPerfCrop,2));
fprintf('gt_cropped size:     %d x %d\n', size(gt_cropped,1),     size(gt_cropped,2));

%% Step 3: corr2 — continuous values, no thresholding
r_normal  = corr2(binaryPerfCrop,     gt_cropped);
r_flipped = corr2(binaryPerfCropFlip, gt_cropped);

fprintf('corr2 normal:  %.4f\n', r_normal);
fprintf('corr2 flipped: %.4f\n', r_flipped);

if r_flipped > r_normal
    fprintf('Using flipped\n');
    binaryPerfFinal = binaryPerfCropFlip;
    r = r_flipped;
else
    fprintf('Using normal\n');
    binaryPerfFinal = binaryPerfCrop;
    r = r_normal;
end

fprintf('binaryPerfFinal size: %d x %d\n', size(binaryPerfFinal,1), size(binaryPerfFinal,2));

%% Step 4: Difference
diffMap = binaryPerfFinal - gt_cropped;

%% Step 5: Display
gtNaturalSize = size(groundTruth);   % [700 x 128]

figure('Color','k','Position',[100 100 1400 800])

subplot(1,4,1)
imshow(imresize(allStrips, gtNaturalSize))
title('Stacked Color Strip','Color','w','FontSize',12)
xlabel('Element','Color','w')
ylabel('Scan File','Color','w')
set(gca,'XColor','w','YColor','w')
axis on

subplot(1,4,2)
imshow(imresize(binaryPerfFinal, gtNaturalSize), [])
colormap(gca, parula)
cb = colorbar; cb.Color = 'w';
title('Binary Performance','Color','w','FontSize',12)
xlabel('Element','Color','w')
ylabel('Scan File','Color','w')
set(gca,'XColor','w','YColor','w','FontSize',11)
axis on

subplot(1,4,3)
imshow(groundTruth, [])
colormap(gca, parula)
cb = colorbar; cb.Color = 'w';
title('Ground Truth','Color','w','FontSize',12)
xlabel('Probe Element','Color','w')
ylabel('Depth Sample','Color','w')
set(gca,'XColor','w','YColor','w','FontSize',11)
axis on

subplot(1,4,4)
imshow(imresize(diffMap, gtNaturalSize), [])
colormap(gca, jet)
cb = colorbar; cb.Color = 'w';
title(sprintf('Difference  |  corr2 = %.3f', r),'Color','w','FontSize',12)
xlabel('Element','Color','w')
ylabel('Scan File','Color','w')
set(gca,'XColor','w','YColor','w','FontSize',11)
axis on

sgtitle('Validation: Stacked Strip vs Ground Truth','Color','w','FontSize',14)