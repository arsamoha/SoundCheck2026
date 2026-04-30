clear; clc;

%% INPUT
inputFolder = 'Data/Image_Scans';
fileList = dir(fullfile(inputFolder, '*.mat'));
numFiles = length(fileList);

if numFiles == 0
    error('No .mat files found.');
end

%% STORAGE
allRatios = zeros(128, numFiles);

%% FIRST PASS — collect allRatios only
for f = 1:numFiles

    fprintf('Pass 1 - Processing %d / %d\n', f, numFiles);

    fullpath = fullfile(inputFolder, fileList(f).name);
    data = load(fullpath);

    if ~isfield(data, 'imgData')
        warning('Skipping %s (no imgData)', fileList(f).name);
        continue;
    end

    imgData = double(data.imgData);

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

end

%% DETECT ACTIVE ELEMENTS
meanRatioPerElement = mean(allRatios, 2);
activityThresh = 0.05;
activeElements = meanRatioPerElement >= activityThresh;

firstActive = find(activeElements, 1, 'first');
lastActive  = find(activeElements, 1, 'last');
activeN     = lastActive - firstActive + 1;

fprintf('firstActive: %d\n', firstActive);
fprintf('lastActive:  %d\n', lastActive);
fprintf('activeN:     %d\n', activeN);

%% SECOND PASS — build color strip matrix directly
thresh_green = 0.5;
stripMatrix = zeros(numFiles, 128, 3);

for f = 1:numFiles
    ratio = allRatios(:, f);
    for e = 1:128
        if ratio(e) == 0
            stripMatrix(f, e, :) = [0.85 0.85 0.85];
        elseif ratio(e) >= thresh_green
            stripMatrix(f, e, :) = [0.2 0.85 0.2];
        else
            stripMatrix(f, e, :) = [0.9 0.1 0.1];
        end
    end
end

allStrips = stripMatrix(:, firstActive:lastActive, :);

outputFile = fullfile(inputFolder, 'overlay_raw_signals.png');
imwrite(uint8(allStrips * 255), outputFile);
fprintf('\nSaved stacked image to:\n%s\n', outputFile);

%% VALIDATION

load Data/Dead_Elements/curvedDeadElements.mat
groundTruth = double(curvedDeadElements);

%% Step 1: Normalize allRatios column-wise
elementMean = mean(allRatios, 2);
elementMean(elementMean == 0) = 1;
allRatiosNorm = allRatios ./ elementMean;
allRatiosNorm = min(allRatiosNorm, 1);

binaryPerf = allRatiosNorm' * 100;

gt_live = (1 - groundTruth) * 100;

gtRows = size(groundTruth, 1);
gtCols = size(groundTruth, 2);
activeN = lastActive - firstActive + 1;

fprintf('binaryPerf size:  %d x %d\n', size(binaryPerf,1), size(binaryPerf,2));
fprintf('groundTruth size: %d x %d\n', gtRows, gtCols);

%% Step 2: Crop binary perf to active columns, resize rows to gtRows
binaryPerfCrop     = binaryPerf(:, firstActive:lastActive);
binaryPerfCropFlip = fliplr(binaryPerfCrop);

if size(binaryPerfCrop,1) ~= gtRows
    binaryPerfResized     = imresize(binaryPerfCrop,     [gtRows, activeN], 'bilinear');
    binaryPerfResizedFlip = imresize(binaryPerfCropFlip, [gtRows, activeN], 'bilinear');
else
    binaryPerfResized     = binaryPerfCrop;
    binaryPerfResizedFlip = binaryPerfCropFlip;
end

%% Step 3: Resize to full [gtRows x gtCols] — stretch horizontally to match GT
binaryPerfResizedFull     = imresize(binaryPerfResized,     [gtRows, gtCols], 'bilinear');
binaryPerfResizedFullFlip = imresize(binaryPerfResizedFlip, [gtRows, gtCols], 'bilinear');

%% Step 4: corr2 on full [700 x 128]
r_normal  = corr2(binaryPerfResizedFull,     gt_live);
r_flipped = corr2(binaryPerfResizedFullFlip, gt_live);

fprintf('corr2 normal:  %.4f\n', r_normal);
fprintf('corr2 flipped: %.4f\n', r_flipped);

if r_flipped > r_normal
    fprintf('Using flipped\n');
    binaryPerfFinal = binaryPerfResizedFullFlip;
    r = r_flipped;
else
    fprintf('Using normal\n');
    binaryPerfFinal = binaryPerfResizedFull;
    r = r_normal;
end

fprintf('binaryPerfFinal size: %d x %d\n', size(binaryPerfFinal,1), size(binaryPerfFinal,2));

%% Step 5: Agreement statistics
perfBinary = binaryPerfFinal >= 50;
gtBinary   = gt_live         >= 50;

bothLive   =  perfBinary &  gtBinary;
bothDead   = ~perfBinary & ~gtBinary;
missedDead =  perfBinary & ~gtBinary;
falseAlarm = ~perfBinary &  gtBinary;

total    = numel(perfBinary);
agree    = sum(bothLive(:)) + sum(bothDead(:));
missed   = sum(missedDead(:));
false_al = sum(falseAlarm(:));

fprintf('\n--- Agreement Summary ---\n')
fprintf('Agreement:            %d / %d = %.1f%%\n', agree,    total, 100*agree/total)
fprintf('Missed dead (red):    %d / %d = %.1f%%\n', missed,   total, 100*missed/total)
fprintf('False alarm (yellow): %d / %d = %.1f%%\n', false_al, total, 100*false_al/total)
fprintf('-------------------------\n')

%% Step 6: imfuse
% Build high-contrast RGB overlay manually
perfMask = binaryPerfFinal >= 50;   % logical
gtMask   = gt_live         >= 50;   % logical

overlap    = perfMask &  gtMask;   % both agree — green
perfOnly   = perfMask & ~gtMask;   % perf says live, GT says dead — red
gtOnly     = ~perfMask &  gtMask;  % GT says live, perf says dead — blue
neither    = ~perfMask & ~gtMask;  % both agree dead — black/dark

R = uint8(255 * (perfOnly  | overlap*0));   % red for perf only
G = uint8(255 * overlap);                   % green for overlap
B = uint8(255 * gtOnly);                    % blue for GT only

fusedOverlay = cat(3, R, G, B);

%% Step 7: Stretch allStrips to full [gtRows x gtCols x 3]
if size(allStrips,1) ~= gtRows || size(allStrips,2) ~= gtCols
    allStripsDisplay = imresize(allStrips, [gtRows, gtCols]);
    allStripsDisplay = max(0, min(1, allStripsDisplay));
else
    allStripsDisplay = allStrips;
end

%% Step 8: Display
figure('Color','k','Position',[100 100 1600 800])

subplot(1,4,1)
imshow(allStripsDisplay)
title('Stacked Color Strip','Color','w','FontSize',12)
xlabel('Element','Color','w')
ylabel('Scan File','Color','w')
set(gca,'XColor','w','YColor','w')
axis on

subplot(1,4,2)
imshow(binaryPerfFinal, [0 100])
colormap(gca, parula)
cb = colorbar; cb.Color = 'w';
title('Binary Performance','Color','w','FontSize',12)
xlabel('Element','Color','w')
ylabel('Scan File','Color','w')
set(gca,'XColor','w','YColor','w','FontSize',11)
axis on

subplot(1,4,3)
imshow(gt_live, [0 100])
colormap(gca, flipud(parula))
cb = colorbar; cb.Color = 'w';
title('Ground Truth','Color','w','FontSize',12)
xlabel('Probe Element','Color','w')
ylabel('Depth Sample','Color','w')
set(gca,'XColor','w','YColor','w','FontSize',11)
axis on

subplot(1,4,4)
imshow(fusedOverlay)
title(sprintf('Overlay  |  corr2 = %.3f  |  Agreement = %.1f%%', ...
    r, 100*agree/total),'Color','w','FontSize',11)
xlabel('Element','Color','w')
ylabel('Scan File','Color','w')
set(gca,'XColor','w','YColor','w','FontSize',11)
axis on

sgtitle('Validation: Stacked Strip vs Ground Truth','Color','w','FontSize',14)