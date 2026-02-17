
clear; close all; clc;

%% Paths
dataDir = '/Users/trisha/Projects/SoundCheck/Verasonics_Testing/LinearArrayImages/unlabled/';  % test directory with .mat
outputDir = '/Users/trisha/Projects/SoundCheck/Linear_Analysis/';  % results saved here

%% Params
threshold = 0.70;  % min acceptable brightness - green for heatmap
minThreshold = 0.50; % yellow-red threshold for heatmap

%% Get all .mat files in the directory
matFiles = dir(fullfile(dataDir, '*.mat'));
numFiles = length(matFiles);

%% Init
allColumnScores = [];
allPercentPerformance = [];
fileNames = {};
allPercentPerRow = {};
dropoutsAll = cell(1, numFiles);

%% Main analysis loop
for fileIdx = 1:numFiles
    fileName = matFiles(fileIdx).name;
    filePath = fullfile(dataDir, fileName);
    fileNames{fileIdx} = fileName;
    
    %fprintf('\n[%d/%d] Processing: %s\n', fileIdx, numFiles, fileName);
    
    try
        % Load img data
        data = load(filePath);
        
        % Extract imgData
        if isfield(data, 'imgData')
            imgData = data.imgData;
        elseif isfield(data, 'imageData')
            imgData = data.imageData;
        else
            % Try to find img data automatically
            fields = fieldnames(data);
            imgData = data.(fields{1});
            warning('Using field %s as image data', fields{1});
        end
        
        % Get img dimensions and percent position for each column
        [numRows, numCols] = size(imgData);
        fprintf('Processing %s: size(imgData) = [%d %d]\n', fileName, numRows, numCols); %TEST
        assert(~isempty(imgData), 'imgData is empty'); %TEST
        numCols = size(imgData, 2); %TEST
        if numCols > 1
            cols = 1:numCols;
            distance = (cols - 1) ./ (numCols - 1) * 100;   % 0..100
        else
            distance = 0;  % single-column edge case
        end
        
        %% Compute column-wise brightness scores (TODO: choose one)
        columnScore = mean(imgData, 1);   
        % columnScore = median(imgData, 1);     
        % columnScore = max(imgData, [], 1);       

        %% Determine ref (max) brightness
        refBrightness = max(columnScore);
        %fprintf('  Reference brightness: %.2f \n', refBrightness);
        
        %% Calculate percent performance
        percentPerformance = (columnScore / refBrightness) * 100;
        percentPerRow = (double(imgData) ./ refBrightness) * 100; % percent performance per row for each column

        %% ID dropout regions
        dropouts = find(percentPerformance < (threshold * 100));
        dropoutsAll{fileIdx} = dropouts; 

        % Store numeric results
        allColumnScores(fileIdx, :) = columnScore;
        allPercentPerformance(fileIdx, :) = percentPerformance;
        allPercentPerRow{fileIdx} = percentPerRow;
        
        % Signal loss
        for rowIdx = 1:numRows
            rowPct = percentPerRow(rowIdx, :);            
            if ~isequal(size(rowPct), [1, numCols])
                error('Row %d: unexpected rowPct size: %s', rowIdx, mat2str(size(rowPct)));
            end
        
            dropMaskRow = rowPct < (threshold * 100);
            droppedCols = find(dropMaskRow);      
        
            if isempty(droppedCols)
                fprintf('[ Image %d/%d ] [ Row %d ] 0.0%% of the array has 0.0%% signal loss\n', ...
                        fileIdx, numFiles, rowIdx);
                continue;
            end
        
            % Print signal loss across the array (for each column)
            for k = 1:numel(droppedCols)
                colIdx = droppedCols(k);
                if numCols > 1
                    arrayDistance = distance(colIdx);  
                else
                    arrayDistance = 0;
                end
                meanPerformance = rowPct(colIdx); 
                signalLoss = 100 - meanPerformance;
        
                fprintf('[ Image %d/%d ] %.1f%% of the array has %.1f%% signal loss\n', ...
                        fileIdx, numFiles, arrayDistance, signalLoss);
            end
        end
        
        %% Heatmap
        % RGB per column
        barHeight = 12;
        pct = percentPerformance / 100;

        % Colors
        redMask = pct < minThreshold;
        yellowMask = pct >= minThreshold & pct < threshold;
        greenMask = pct >= threshold;

        % Build heatbar
        barHeight = 20;
        heatbar = zeros(barHeight, numel(pct), 3);
        if any(redMask)
            heatbar(:, redMask, :) = repmat(reshape([1 0 0],1,1,3), barHeight, sum(redMask));
        end
        if any(yellowMask)
            heatbar(:, yellowMask, :) = repmat(reshape([1 1 0],1,1,3), barHeight, sum(yellowMask));
        end
        if any(greenMask)
            heatbar(:, greenMask, :) = repmat(reshape([0 1 0],1,1,3), barHeight, sum(greenMask));
        end

        % Display with original image
        figure('Name', fileName, 'NumberTitle', 'off');
        subplot(2,1,1);
        imagesc(imgData); colormap gray; axis image off; title('Image');
        subplot(2,1,2);
        imshow(heatbar); axis off;
        title(sprintf('Column Performance: < %d%% (red), %d-%d%% (yellow), ≥ %d%% (green)', minThreshold*100, minThreshold*100, threshold*100, threshold*100));

    end
end

%% Save numerical results
resultsFile = fullfile(outputDir, 'analysis_results.mat');
save(resultsFile, 'allColumnScores', 'allPercentPerformance', 'allPercentPerRow', 'fileNames', 'threshold');
fprintf('Saved: analysis_results.mat\n');
fprintf('Results saved to: %s\n', outputDir);