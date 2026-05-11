clear; close all; clc;

%% Paths
% dataDir   = 'Verasonics_Testing/LinearArrayImages/labeled/five_contiguous_off/';
dataDir        = 'SC2026test01/SC2026test01Stills/';
outputDir      = 'Analysis/Linear/';
% refControlFile = 'Verasonics_Testing/LinearArrayImages/labeled/control/control.mat';
refControlFile = '';

%% Hardcoded metadata
% Each row: {probe, gain_dB, depth_cm, focus}
acquisitionMeta = {
    1, 20, 3.9, 'Shallow';
    1, 30, 3.9, 'Shallow';
    1, 40, 3.9, 'Shallow';
    1, 50, 3.9, 'Shallow';
    1, 60, 3.9, 'Shallow';
    1, 40, 4.0, 'Deep';
    2, 20, 3.9, 'Shallow';
    2, 30, 3.9, 'Shallow';
    2, 40, 3.9, 'Shallow';
    2, 50, 3.9, 'Shallow';
    2, 60, 3.9, 'Shallow';
    2, 40, 4.0, 'Deep';
    3, 20, 3.9, 'Shallow';
    3, 30, 3.9, 'Shallow';
    3, 40, 3.9, 'Shallow';
    3, 50, 3.9, 'Shallow';
    3, 60, 3.9, 'Shallow';
    3, 40, 4.0, 'Deep';
    4, 20, 3.9, 'Shallow';
    4, 30, 3.9, 'Shallow';
    4, 40, 3.9, 'Shallow';
    4, 50, 3.9, 'Shallow';
    4, 60, 3.9, 'Shallow';
    4, 40, 4.0, 'Deep';
};

%% Params
threshold    = 0.70; % green threshold (0..1)
minThreshold = 0.50; % yellow threshold (0..1)

% Variation plot: significance thresholds
zThresh        = 3.0;
madThresh      = 4.0;
tolAbs         = 1.0;
minVarFloor    = 0.1;
neighborRadius = 3;

% Scan area crop (PNG only, ignored for .mat)
cropRowStart  = 0.069;
cropRowEnd    = 0.208;
cropColStart  = 0.292;
cropColEnd    = 0.836;
colTrimThresh = 0.20;  % fraction of max col mean below which cols are trimmed

% Row exclusion: rows below this fraction of max row mean are treated as dark gaps
rowDarkThresh = 0.10;

% Label masking
labelBrightPct  = 95;
labelRowMaxDens = 0.30;

%% Colors
sliceColors = [0.15 0.65 0.15;
               0.95 0.75 0.10;
               0.85 0.15 0.15];
textColor   = [0 0 0];

%% Get files (.mat or .png)
matFiles = dir(fullfile(dataDir, '*.mat'));
pngFiles = dir(fullfile(dataDir, '*.png'));
if ~isempty(matFiles)
    dataFiles = matFiles;
    fileType  = 'mat';
elseif ~isempty(pngFiles)
    dataFiles = pngFiles;
    fileType  = 'png';
else
    error('No .mat or .png files found in %s', dataDir);
end
numFiles = numel(dataFiles);

%% Containers
allColumnScores       = [];
allPercentPerformance = [];
allPercentPerRow      = {};
fileNames             = {};
dropoutsAll           = cell(1, numFiles);
rAll                  = NaN(1, numFiles);
pctLossAll            = NaN(1, numFiles);
pctColsLostAll        = NaN(1, numFiles);
greenPctAll           = NaN(1, numFiles);
yellowPctAll          = NaN(1, numFiles);
redPctAll             = NaN(1, numFiles);

%% Load control reference
refPctMean = [];
R          = struct();
if ~isempty(refControlFile) && exist(refControlFile, 'file')
    [~, ~, ctrlExt] = fileparts(refControlFile);
    if strcmpi(ctrlExt, '.png')
        raw = imread(refControlFile);
        if size(raw, 3) == 3, raw = rgb2gray(raw); end
        ctrlImg   = double(raw);
        ctrlScore = mean(ctrlImg, 1);
        ctrlMaxBr = max(ctrlScore);
        if ctrlMaxBr > 0, refPctMean = (ctrlScore / ctrlMaxBr) * 100; end
    else
        R = load(refControlFile);
        if isfield(R, 'imgData') || isfield(R, 'imageData')
            if isfield(R, 'imgData'), ctrlImg = double(R.imgData);
            else,                     ctrlImg = double(R.imageData); end
            ctrlScore = mean(ctrlImg, 1);
            ctrlMaxBr = max(ctrlScore);
            if ctrlMaxBr > 0, refPctMean = (ctrlScore / ctrlMaxBr) * 100; end
        elseif isfield(R, 'allPercentPerformance') && ~isempty(R.allPercentPerformance)
            refPctMean = mean(R.allPercentPerformance, 1, 'omitnan');
        elseif isfield(R, 'percentPerformance') && ~isempty(R.percentPerformance)
            refPctMean = R.percentPerformance;
        end
    end
end
if isempty(refPctMean)
    fprintf('No control reference — overlay and correlation disabled.\n');
end

%% Main loop
for fi = 1:numFiles
    fileName      = dataFiles(fi).name;
    filePath      = fullfile(dataDir, fileName);
    fileNames{fi} = fileName;

    try
        %% Load image data
        if strcmp(fileType, 'png')
            raw = imread(filePath);
            if size(raw, 3) == 3, raw = rgb2gray(raw); end
            imgData = double(raw);
        else
            S = load(filePath);
            if isfield(S, 'imgData'),      imgData = S.imgData;
            elseif isfield(S, 'imageData'), imgData = S.imageData;
            else
                fn = fieldnames(S); imgData = S.(fn{1});
                warning('Using field "%s" as image data for %s', fn{1}, fileName);
            end
        end
        assert(~isempty(imgData), 'imgData empty');
        [nRows, nCols] = size(imgData);

        %% Distance vector
        if strcmp(fileType, 'mat') && isfield(S, 'distance') && numel(S.distance) == nCols
            distance = S.distance;
        elseif strcmp(fileType, 'mat') && isfield(S, 'distance_mm') && numel(S.distance_mm) == nCols
            distance = S.distance_mm;
        else
            distance = (0:(nCols-1)) * 0.3;
        end

        %% Crop to scan area (PNG only)
        if strcmp(fileType, 'png')
            r1 = max(1,     round(cropRowStart * nRows));
            r2 = min(nRows, round(cropRowEnd   * nRows));
            c1 = max(1,     round(cropColStart * nCols));
            c2 = min(nCols, round(cropColEnd   * nCols));
            imgData        = imgData(r1:r2, c1:c2);
            [nRows, nCols] = size(imgData);
            distance       = (0:(nCols-1)) * 0.3;
        end

        %% Auto-trim right edge only (left is fixed by cropColStart)
        % Scan right-to-left
        if strcmp(fileType, 'png')
            colMeansRaw = mean(double(imgData), 1);
            colThresh   = max(colMeansRaw) * colTrimThresh;
            minRun      = 10;
            lastActive  = nCols;
            c = nCols;
            while c > minRun
                if all(colMeansRaw(c-minRun+1:c) > colThresh)
                    lastActive = c;
                    break;
                end
                c = c - 1;
            end
            lastActive = max(1, lastActive - 1);  % trim one extra boundary col
            if lastActive < nCols
                imgData        = imgData(:, 1:lastActive);
                [nRows, nCols] = size(imgData);
                distance       = (0:(nCols-1)) * 0.3;
            end
        end

        %% Auto-detect and mask bright label overlays
        imgDouble    = double(imgData);
        brightThresh = prctile(imgDouble(imgDouble > 0), labelBrightPct);
        brightMask   = imgDouble > brightThresh;
        kSize        = 3;
        conv1        = conv2(double(brightMask), ones(kSize), 'same');
        eroded       = conv1 >= kSize^2;
        conv2out     = conv2(double(eroded), ones(kSize), 'same');
        labelMask    = conv2out > 0;
        rowDensity   = mean(labelMask, 2);
        textRows     = rowDensity > 0 & rowDensity < labelRowMaxDens;
        labelMaskFiltered = labelMask & repmat(textRows, 1, size(labelMask,2));
        imgScoring   = imgDouble;
        imgScoring(labelMaskFiltered) = NaN;
        maskedFracPerCol = mean(labelMaskFiltered, 1);
        imgScoring(:, maskedFracPerCol > 0.15) = NaN;

        %% Column scoring
        rowMeans   = mean(imgScoring, 2, 'omitnan');
        % Use 90th percentile of row means as reference to avoid single bright
        % artifact rows
        rowMeansRef = prctile(rowMeans(~isnan(rowMeans)), 90);
        activeRows  = rowMeans > rowDarkThresh * rowMeansRef;
        imgForScore = imgScoring;
        imgForScore(~activeRows, :) = NaN;
        columnScore   = mean(imgForScore, 1, 'omitnan');
        refBrightness = max(columnScore);
        if refBrightness == 0 || isnan(refBrightness)
            warning('%s: reference brightness zero — skipping', fileName);
            continue;
        end
        percentPerformance = (columnScore / refBrightness) * 100;
        pctNorm            = percentPerformance / 100;
        percentPerRow      = (imgForScore ./ refBrightness) * 100;

        %% Control reference overlay
        refOverlayPct = [];
        if ~isempty(refPctMean)
            if numel(refPctMean) == nCols
                refOverlayPct = refPctMean;
            else
                if isfield(R, 'distance') && numel(R.distance) == numel(refPctMean)
                    refDistance = R.distance;
                elseif isfield(R, 'distance_mm') && numel(R.distance_mm) == numel(refPctMean)
                    refDistance = R.distance_mm;
                else
                    refDistance = linspace(min(distance), max(distance), numel(refPctMean));
                end
                [refDistanceSorted, idxs] = sort(refDistance);
                refOverlayPct = interp1(refDistanceSorted, refPctMean(idxs), distance, 'linear', 'extrap');
            end
            refOverlayPct = max(0, min(100, refOverlayPct));
        end

        %% Pearson r vs. control
        r = NaN;
        if ~isempty(refOverlayPct)
            a = percentPerformance(:); b = refOverlayPct(:);
            valid = ~isnan(a) & ~isnan(b);
            if any(valid)
                C = corrcoef(a(valid), b(valid));
                r = C(1,2); rAll(fi) = r;
                fprintf('[Image %d/%d] r = %.3f\n', fi, numFiles, r);
            end
        end

        %% Store results
        allColumnScores(fi, 1:nCols)       = columnScore;
        allPercentPerformance(fi, 1:nCols) = percentPerformance;
        allPercentPerRow{fi}               = percentPerRow;

        %% Dropouts & summary
        dropouts           = find(percentPerformance < threshold * 100);
        dropoutsAll{fi}    = dropouts;
        percentLoss        = mean(100 - percentPerformance);
        percentColumnsLost = 100 * numel(dropouts) / nCols;
        pctLossAll(fi)     = percentLoss;
        pctColsLostAll(fi) = percentColumnsLost;

        %% Per-row console output
        for rowIdx = 1:nRows
            rowPct      = percentPerRow(rowIdx, :);
            droppedCols = find(rowPct < threshold * 100);
            if isempty(droppedCols), continue; end
            for k = 1:numel(droppedCols)
                colIdx = droppedCols(k);
                if nCols > 1 && max(distance) ~= min(distance)
                    arrayPct = 100*(distance(colIdx)-min(distance))/(max(distance)-min(distance));
                else
                    arrayPct = 100*(colIdx-1)/max(nCols-1,1);
                end
                fprintf('[Image %d/%d] %.1f%% of the array has %.1f%% signal loss\n', ...
                        fi, numFiles, arrayPct, 100-percentPerformance(colIdx));
            end
        end

        %% Heatbar
        barHeight  = 20;
        redMask    = pctNorm <  minThreshold;
        yellowMask = pctNorm >= minThreshold & pctNorm < threshold;
        greenMask  = pctNorm >= threshold;
        heatbar    = zeros(barHeight, nCols, 3);
        masks      = {greenMask, yellowMask, redMask};
        for band = 1:3
            if any(masks{band})
                heatbar(:,masks{band},:) = repmat(reshape(sliceColors(band,:),1,1,3), barHeight, sum(masks{band}));
            end
        end
        counts    = [sum(greenMask), sum(yellowMask), sum(redMask)];
        totalCols = sum(counts);
        greenPctAll(fi)  = 100*counts(1)/totalCols;
        yellowPctAll(fi) = 100*counts(2)/totalCols;
        redPctAll(fi)    = 100*counts(3)/totalCols;

        %% Dead elements mask (.mat only)
        deMask = false(1, nCols);
        if strcmp(fileType, 'mat') && isfield(S, 'deadElements')
            deIn = S.deadElements;
        else
            deIn = [];
        end
        if ~isempty(deIn)
            if islogical(deIn) && numel(deIn) == nCols
                deMask = deIn(:)';
            elseif isnumeric(deIn)
                if numel(deIn)==nCols && all(ismember(unique(deIn(~isnan(deIn))),[0 1]))
                    deMask = logical(deIn(:)');
                elseif all(deIn==floor(deIn)) && all(deIn>=1) && all(deIn<=nCols)
                    deMask(unique(deIn(:)')) = true;
                else
                    raw = deIn(~isnan(deIn) & deIn==floor(deIn) & deIn>=1 & deIn<=nCols);
                    if ~isempty(raw), deMask(unique(raw)) = true;
                        warning('deadElements had invalid entries — using valid indices only');
                    elseif numel(deIn)==nCols
                        deMask = logical(deIn(:)'~=0);
                        warning('deadElements interpreted as nonzero mask');
                    else
                        fprintf('deadElements: no valid indices for nCols=%d\n', nCols);
                    end
                end
            elseif iscell(deIn)
                try
                    deIn = cell2mat(deIn);
                    raw  = deIn(~isnan(deIn) & deIn==floor(deIn) & deIn>=1 & deIn<=nCols);
                    if ~isempty(raw), deMask(unique(raw)) = true; end
                catch
                    fprintf('deadElements cell could not be parsed — skipping\n');
                end
            else
                fprintf('deadElements unsupported type (%s) — skipping\n', class(deIn));
            end
        end

        %% Figure
        fig = figure('Name', fileName, 'NumberTitle', 'off', ...
                     'Color', 'white', 'Visible', 'on', 'InvertHardcopy', 'off');
        tl  = tiledlayout(fig, 3, 2, 'TileSpacing', 'loose', 'Padding', 'compact');

        if ~isnan(r)
            tlTitle = sprintf('%s\nr = %.3f  |  %.1f%% signal loss across %.1f%% of array', ...
                              fileName, r, percentLoss, percentColumnsLost);
        else
            tlTitle = sprintf('%s\n%.1f%% signal loss across %.1f%% of array', ...
                              fileName, percentLoss, percentColumnsLost);
        end
        title(tl, tlTitle, 'FontSize', 9, 'FontWeight', 'normal', 'Color', textColor, 'Interpreter', 'none');

        % Ultrasound image
        axImg = nexttile(tl, 1, [1 2]);
        imagesc(imgData, 'Parent', axImg);
        colormap(axImg, gray);
        axis(axImg, 'image', 'off');
        title(axImg, 'Ultrasound Image', 'Color', textColor, 'FontWeight', 'normal');

        % Bar graph
        axBar = nexttile(tl, 3);
        hb    = bar(axBar, 1:nCols, pctNorm*100, 1, 'EdgeColor', 'none', 'FaceColor', 'flat');
        hb.CData = assignBarColors(pctNorm, minThreshold, threshold, sliceColors);
        set(axBar, 'Color', 'white', 'Box', 'off', 'TickDir', 'out');
        axBar.XColor = textColor; axBar.YColor = textColor;
        xlim(axBar, [1 nCols]); ylim(axBar, [0 100]);
        xTickPos = round(linspace(1, nCols, 5));
        set(axBar, 'XTick', xTickPos, 'XTickLabel', {'0%','25%','50%','75%','100%'});
        xlabel(axBar, '% Array', 'Color', textColor);
        ylabel(axBar, '% Signal', 'Color', textColor);
        title(axBar, 'Percent Signal', 'Color', textColor, 'FontWeight', 'normal');
        hold(axBar, 'on');
        hGreen  = patch(axBar, NaN, NaN, sliceColors(1,:), 'EdgeColor', 'none');
        hYellow = patch(axBar, NaN, NaN, sliceColors(2,:), 'EdgeColor', 'none');
        hRed    = patch(axBar, NaN, NaN, sliceColors(3,:), 'EdgeColor', 'none');
        if ~isempty(refOverlayPct)
            hCtrl = plot(axBar, 1:nCols, refOverlayPct, '-k', 'LineWidth', 1.5);
            lg = legend(axBar, [hGreen,hYellow,hRed,hCtrl], {'>70%','50–70%','<50%','Control'}, ...
                        'Location','southoutside','Orientation','horizontal');
        else
            lg = legend(axBar, [hGreen,hYellow,hRed], {'>70%','50–70%','<50%'}, ...
                        'Location','southoutside','Orientation','horizontal');
        end
        set(lg, 'TextColor', textColor, 'Box', 'on', 'Color', 'white');
        try, lg.EdgeColor = textColor; catch, end
        hold(axBar, 'off');

        % Pie chart
        axPie = nexttile(tl, 4);
        if totalCols > 0
            pobj = pie(axPie, counts);
            for kk = 1:floor(numel(pobj)/2)
                set(pobj(2*kk-1), 'FaceColor', sliceColors(kk,:), 'EdgeColor', 'k');
                set(pobj(2*kk),   'Color', textColor);
            end
        else
            text(0.5,0.5,'No columns','HorizontalAlignment','center','Parent',axPie,'Color',textColor);
            axis(axPie,'off');
        end
        title(axPie, 'Quality Distribution', 'Color', textColor, 'FontWeight', 'normal');
        axPie.Title.Units       = 'normalized';
        axPie.Title.Position(2) = axPie.Title.Position(2) + 0.08;

        % Heatbar
        axHeat = nexttile(tl, 5);
        imshow(heatbar, 'Parent', axHeat);
        axis(axHeat, 'off');
        title(axHeat, 'Heatbar', 'Color', textColor, 'FontWeight', 'normal');
        if any(deMask) && isgraphics(axHeat)
            d = [0,deMask,0]; edges = d(2:end)-d(1:end-1);
            starts = find(edges==1); ends = find(edges==-1)-1;
            valid  = starts>=1 & ends<=nCols & starts<=ends;
            starts = starts(valid); ends = ends(valid);
            if ~isempty(starts)
                set(axHeat,'YDir','normal'); hold(axHeat,'on');
                for rr = 1:numel(starts)
                    rectangle(axHeat,'Position',[starts(rr)-0.5,0.5,ends(rr)-starts(rr)+1,barHeight],...
                              'EdgeColor','k','LineWidth',2,'FaceColor','none');
                end
                hold(axHeat,'off');
            end
        end

        % Variation plot
        axVar = nexttile(tl, 6);
        set(axVar, 'Color','white','Box','off','TickDir','out','XColor',textColor,'YColor',textColor);
        title(axVar, 'Signal Change vs. Control', 'Color', textColor, 'FontWeight', 'normal');
        if any(deMask) && ~isempty(refOverlayPct)
            varBar = zeros(1,nCols); varBar(deMask) = percentPerformance(deMask);
            hVarBar = bar(axVar,1:nCols,varBar,1,'FaceColor','flat','EdgeColor','none');
            hVarBar.CData = assignBarColors(pctNorm,minThreshold,threshold,sliceColors);
            pctChange = percentPerformance - refOverlayPct;
            absDiff  = abs(pctChange);
            sigmaAbs = max(std(absDiff), minVarFloor);
            medAbs   = median(absDiff);
            madAbs   = max(median(abs(absDiff-medAbs)), minVarFloor);
            sigMask  = ((absDiff>zThresh*sigmaAbs)|(absDiff>madThresh*madAbs)) & (absDiff>tolAbs);
            sigMaskDilated = sigMask;
            for shift = 1:neighborRadius
                sigMaskDilated = sigMaskDilated | [false(1,shift),sigMask(1:end-shift)] ...
                                               | [sigMask(shift+1:end),false(1,shift)];
            end
            lineData = zeros(1,nCols); lineData(sigMaskDilated) = abs(pctChange(sigMaskDilated));
            set(axVar,'Color','white','Box','off','TickDir','out','XColor',textColor,'YColor',textColor);
            xlim(axVar,[1 nCols]);
            yLim = max(abs(pctChange(sigMaskDilated|deMask)));
            ylim(axVar,[0,max(yLim+5,10)]);
            set(axVar,'XTick',xTickPos,'XTickLabel',{'0%','25%','50%','75%','100%'});
            xlabel(axVar,'% Array','Color',textColor);
            ylabel(axVar,'% Change (vs Control)','Color',textColor);
            hold(axVar,'on');
            plot(axVar,1:nCols,lineData,'-k','LineWidth',1.8);
            hold(axVar,'off');
            hRedSwatch  = patch(axVar,NaN,NaN,sliceColors(3,:),'EdgeColor','none');
            hLineSwatch = line(axVar,NaN,NaN,'Color','k','LineWidth',1.8);
            lgVar = legend(axVar,[hRedSwatch,hLineSwatch],{'Dead element','% change'},...
                           'Location','southoutside','Orientation','horizontal');
            set(lgVar,'TextColor',textColor,'Box','on','Color','white');
            try, lgVar.EdgeColor = textColor; catch, end
        else
            text(0.5,0.5,'No dead elements / no control reference',...
                 'HorizontalAlignment','center','Units','normalized',...
                 'Parent',axVar,'Color',textColor,'Interpreter','none');
            axis(axVar,'off');
        end

        %% Save per-image PDF
        %{
        if ~exist(outputDir, 'dir'), mkdir(outputDir); end
        pdfFile = fullfile(outputDir, [fileName(1:end-4) '.pdf']);
        exportgraphics(fig, pdfFile, 'ContentType', 'vector', 'BackgroundColor', 'white');
        fprintf('[Image %d/%d] Saved PDF: %s\n', fi, numFiles, pdfFile);
        close(fig);
        %}

    catch ME
        fprintf('Error processing %s: %s\n', fileName, ME.message);
        for s = 1:numel(ME.stack)
            fprintf('  %d: %s (line %d)\n', s, ME.stack(s).name, ME.stack(s).line);
        end
    end
end

%% Gain vs Signal and Focus vs Signal correlation
meanSignalAll = 100 - pctLossAll;  % NaN where pctLossAll is NaN

gainAll  = NaN(1, numFiles);
focusNum = NaN(1, numFiles);
nMeta    = size(acquisitionMeta, 1);
for i = 1:min(nMeta, numFiles)
    gainAll(i) = acquisitionMeta{i,2};
    foc = acquisitionMeta{i,4};
    if     strcmpi(foc,'Shallow'), focusNum(i) = 0;
    elseif strcmpi(foc,'Deep'),    focusNum(i) = 1;
    end
end

rGain = NaN; rFocus = NaN;
validGain  = ~isnan(gainAll)  & ~isnan(meanSignalAll);
validFocus = ~isnan(focusNum) & ~isnan(meanSignalAll);
if any(validGain)
    Cg = corrcoef(gainAll(validGain), meanSignalAll(validGain));
    rGain = Cg(1,2);
end
if any(validFocus)
    Cf = corrcoef(focusNum(validFocus), meanSignalAll(validFocus));
    rFocus = Cf(1,2);
end
if ~isnan(rGain),  fprintf('\nGain  vs Mean Signal: r = %.3f\n', rGain);
else,              fprintf('\nGain  vs Mean Signal: r = N/A\n'); end
if ~isnan(rFocus), fprintf('Focus vs Mean Signal: r = %.3f\n', rFocus);
else,              fprintf('Focus vs Mean Signal: r = N/A\n'); end

%% Gain effect summary table
gainLevels = [20 30 40 50 60];
fprintf('\nGain Effect on Mean Signal %% (Shallow Focus)\n');
fprintf('  Calculated as: mean(100 - signal_loss), normalised to brightest column per image\n');
fprintf('  %-8s', 'Probe');
for gi = 1:numel(gainLevels), fprintf('  %6s', sprintf('%d dB',gainLevels(gi))); end
fprintf('  %-30s\n', '  Recommendation');
fprintf('  %s\n', repmat('-', 1, 8 + numel(gainLevels)*8 + 32));

for probe = 1:4
    gainSignals = NaN(1, numel(gainLevels));
    for gi = 1:numel(gainLevels)
        g    = gainLevels(gi);
        idxs = find(arrayfun(@(i) acquisitionMeta{i,1}==probe && ...
                                   acquisitionMeta{i,2}==g    && ...
                                   strcmp(acquisitionMeta{i,4},'Shallow'), 1:numFiles));
        if ~isempty(idxs)
            gainSignals(gi) = mean(meanSignalAll(idxs), 'omitnan');
        end
    end
    fprintf('  %-8s', sprintf('P%d', probe));
    for gi = 1:numel(gainLevels)
        if isnan(gainSignals(gi)), fprintf('  %6s', 'N/A');
        else,                      fprintf('  %5.1f%%', gainSignals(gi)); end
    end
    % Recommends gain(s) within 2% of maximum
    if any(~isnan(gainSignals))
        maxVal = max(gainSignals, [], 'omitnan');
        tieIdx = find(~isnan(gainSignals) & (maxVal - gainSignals) <= 2);
        if numel(tieIdx) == 1
            recStr = sprintf('%d dB', gainLevels(tieIdx));
        elseif numel(tieIdx) <= 3
            recStr = strjoin(arrayfun(@(g) sprintf('%d dB',g), gainLevels(tieIdx), 'UniformOutput',false), ', ');
        else
            [~,maxIdx] = max(gainSignals);
            recStr = sprintf('%d dB (multiple gains within 2%%)', gainLevels(maxIdx));
        end
    else
        recStr = 'N/A';
    end
    fprintf('  %s\n', recStr);
end

%% Focus effect summary table
fprintf('\nFocus Effect on Mean Signal %% (40 dB)\n');
fprintf('  Calculated as: mean(100 - signal_loss) at shallow vs deep focus\n');
fprintf('  %-8s  %-10s  %-10s  %-12s  %s\n', 'Probe','Shallow','Deep','Diff (D-S)','Recommendation');
fprintf('  %s\n', repmat('-', 1, 60));
focusList = {'Shallow','Deep'};
for probe = 1:4
    focusSignals = NaN(1,2);
    for fi2 = 1:2
        idxs = find(arrayfun(@(i) acquisitionMeta{i,1}==probe && ...
                                   acquisitionMeta{i,2}==40   && ...
                                   strcmp(acquisitionMeta{i,4},focusList{fi2}), 1:numFiles));
        if ~isempty(idxs)
            focusSignals(fi2) = mean(meanSignalAll(idxs), 'omitnan');
        end
    end
    shStr = sprintf('%.1f%%', focusSignals(1));  if isnan(focusSignals(1)), shStr = 'N/A'; end
    dpStr = sprintf('%.1f%%', focusSignals(2));  if isnan(focusSignals(2)), dpStr = 'N/A'; end
    if ~any(isnan(focusSignals))
        d = focusSignals(2) - focusSignals(1);
        if     d >  2, rec = 'deep focus';
        elseif d < -2, rec = 'shallow focus';
        else,          rec = 'either focus'; end
        diffStr = sprintf('%+.1f%%', d);
    else
        diffStr = 'N/A'; rec = 'N/A';
    end
    fprintf('  %-8s  %-10s  %-10s  %-12s  %s\n', sprintf('P%d',probe), shStr, dpStr, diffStr, rec);
end

%% Probe pair comparison: P1 vs P2 and P3 vs P4
% For each gain/focus condition, compute the difference in mean signal
% between each probe in the pair, then correlate their vectors across conditions

probePairs    = {[1 2], [3 4]};
pairLabels    = {'P1 vs P2', 'P3 vs P4'};
diffLabels    = {'P1-P2',    'P3-P4'};

% Build all unique conditions
condGains  = cell2mat(acquisitionMeta(:,2));
condFocus  = acquisitionMeta(:,4);
[~, uIdx]  = unique([condGains, strcmp(condFocus,'Deep')], 'rows');
uGains     = condGains(uIdx);
uFocus     = condFocus(uIdx);
% Sort by shallow first, then by gain ascending
[~, sortOrd] = sortrows([strcmp(uFocus,'Deep'), uGains]);
uGains = uGains(sortOrd);
uFocus = uFocus(sortOrd);
nConds = numel(uGains);

% Condition labels for table and figures
condLabels = arrayfun(@(i) sprintf('%d dB / %s', uGains(i), uFocus{i}), ...
                      (1:nConds)', 'UniformOutput', false);

fprintf('\n%s\n', repmat('=', 1, 72));
fprintf('Probe Pair Comparison\n');
fprintf('%s\n', repmat('=', 1, 72));

% Store signals for figure generation
pairSigAll = cell(numel(probePairs), 2);  % {pair, probe index}

for pp = 1:numel(probePairs)
    pA = probePairs{pp}(1);
    pB = probePairs{pp}(2);
    label     = pairLabels{pp};
    diffLabel = diffLabels{pp};

    % Collect mean signal for each probe across conditions
    sigA = NaN(1, nConds);
    sigB = NaN(1, nConds);
    for ci = 1:nConds
        g   = uGains(ci);
        foc = uFocus{ci};

        idxA = find(arrayfun(@(i) acquisitionMeta{i,1}==pA && ...
                                   acquisitionMeta{i,2}==g  && ...
                                   strcmp(acquisitionMeta{i,4},foc), 1:numFiles));
        idxB = find(arrayfun(@(i) acquisitionMeta{i,1}==pB && ...
                                   acquisitionMeta{i,2}==g  && ...
                                   strcmp(acquisitionMeta{i,4},foc), 1:numFiles));

        if ~isempty(idxA), sigA(ci) = mean(meanSignalAll(idxA), 'omitnan'); end
        if ~isempty(idxB), sigB(ci) = mean(meanSignalAll(idxB), 'omitnan'); end
    end

    pairSigAll{pp,1} = sigA;
    pairSigAll{pp,2} = sigB;

    % r between the two probes' signal vectors across all conditions
    validPair = ~isnan(sigA) & ~isnan(sigB);
    if sum(validPair) >= 2
        Cpp   = corrcoef(sigA(validPair), sigB(validPair));
        rPair = Cpp(1,2);
        rStr  = sprintf('%.3f', rPair);
    else
        rPair = NaN;
        rStr  = 'N/A (insufficient data)';
    end

    % Difference table
    fprintf('\n%s  |  r = %s\n', label, rStr);
    fprintf('  Difference = %s signal (%%)\n', diffLabel);
    fprintf('  %-18s  %8s  %8s  %10s\n', 'Condition', ...
            sprintf('P%d', pA), sprintf('P%d', pB), diffLabel);
    fprintf('  %s\n', repmat('-', 1, 50));

    for ci = 1:nConds
        aStr = 'N/A'; bStr = 'N/A'; dStr = 'N/A';
        if ~isnan(sigA(ci)), aStr = sprintf('%.1f%%', sigA(ci)); end
        if ~isnan(sigB(ci)), bStr = sprintf('%.1f%%', sigB(ci)); end
        if ~isnan(sigA(ci)) && ~isnan(sigB(ci))
            d    = sigA(ci) - sigB(ci);
            dStr = sprintf('%+.1f%%', d);
        end
        fprintf('  %-18s  %8s  %8s  %10s\n', condLabels{ci}, aStr, bStr, dStr);
    end

    % Summary: min absolute difference (condition of best agreement)
    absDiffs  = abs(sigA - sigB);
    validIdxs = find(validPair);
    if ~isempty(validIdxs)
        [minAbsDiff, minRel] = min(absDiffs(validPair));
        bestCondIdx = validIdxs(minRel);
        fprintf('  %s\n', repmat('-', 1, 50));
        fprintf('  Min absolute difference (%s):  %.2f%%  (at %s)\n', ...
                diffLabel, minAbsDiff, condLabels{bestCondIdx});
    end
    fprintf('\n');
end
fprintf('%s\n\n', repmat('=', 1, 72));

%% Probe pair bar charts (one figure per pair)
pairFigTitles = {'Probe Pair P1 & P2: Signal by Gain/Focus', ...
                 'Probe Pair P3 & P4: Signal by Gain/Focus'};
pairBarColors = {[0.20 0.50 0.80; 0.85 0.33 0.10], ...   % blue/orange P1/P2
                 [0.13 0.63 0.35; 0.64 0.19 0.64]};       % green/purple P3/P4

for pp = 1:numel(probePairs)
    pA   = probePairs{pp}(1);
    pB   = probePairs{pp}(2);
    sigA = pairSigAll{pp,1};
    sigB = pairSigAll{pp,2};
    cols = pairBarColors{pp};

    figPair = figure('Name', pairFigTitles{pp}, 'NumberTitle', 'off', ...
                     'Color', 'white', 'InvertHardcopy', 'off');
    axPair  = axes(figPair);

    % Grouped bar: rows = conditions, cols = [pA, pB]
    barData = [sigA(:), sigB(:)];
    hBar    = bar(axPair, barData, 'grouped');
    hBar(1).FaceColor = cols(1,:);
    hBar(2).FaceColor = cols(2,:);
    hBar(1).EdgeColor = 'none';
    hBar(2).EdgeColor = 'none';

    set(axPair, 'Color', 'white', 'Box', 'off', 'TickDir', 'out', ...
                'XColor', [0 0 0], 'YColor', [0 0 0]);
    xlim(axPair, [0.5, nConds + 0.5]);
    ylim(axPair, [0, 108]);
    ylabel(axPair, 'Mean Signal (%)', 'Color', [0 0 0]);
    xlabel(axPair, 'Gain / Focus Condition', 'Color', [0 0 0]);
    set(axPair, 'XTick', 1:nConds, 'XTickLabel', condLabels, ...
                'XTickLabelRotation', 30);
    title(axPair, pairFigTitles{pp}, 'Color', [0 0 0], ...
          'FontWeight', 'normal', 'Interpreter', 'none');

    % Value labels above each bar
    hold(axPair, 'on');
    for ci = 1:nConds
        vals = [sigA(ci), sigB(ci)];
        xPos = [hBar(1).XEndPoints(ci), hBar(2).XEndPoints(ci)];
        for k = 1:2
            if ~isnan(vals(k))
                text(axPair, xPos(k), vals(k) + 0.8, sprintf('%.1f', vals(k)), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                     'FontSize', 7, 'Color', [0 0 0]);
            end
        end
    end
    hold(axPair, 'off');

    lgPair = legend(axPair, hBar, {sprintf('P%d', pA), sprintf('P%d', pB)}, ...
                    'Location', 'southoutside', 'Orientation', 'horizontal');
    set(lgPair, 'TextColor', [0 0 0], 'Box', 'on', 'Color', 'white');
    try, lgPair.EdgeColor = [0 0 0]; catch, end
end

%% Save .mat results
%{
resultsFile = fullfile(outputDir, 'two_contiguous_off.mat');
save(resultsFile, 'allColumnScores', 'allPercentPerformance', 'allPercentPerRow', 'fileNames', 'threshold');
fprintf('Saved results to %s\n', resultsFile);
%}

%% Local functions
function cData = assignBarColors(pctNorm, minThreshold, threshold, sliceColors)
    nCols = numel(pctNorm);
    cData = zeros(nCols, 3);
    for k = 1:nCols
        if     pctNorm(k) < minThreshold, cData(k,:) = sliceColors(3,:);
        elseif pctNorm(k) < threshold,    cData(k,:) = sliceColors(2,:);
        else,                              cData(k,:) = sliceColors(1,:);
        end
    end
end
