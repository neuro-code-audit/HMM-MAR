function graphs = makeBrainGraph(hmm,parcellation_file,maskfile,...
    centergraphs,scalegraphs,partialcorr,threshold,outputfile)
% Project HMM connectomes into brain space for visualisation  
%
% hmm: hmm struct as comes out of hmmmar
% parcellation_file is either a nifti or a cifti file, containing either a
%   parcellation or an ICA decomposition
% maskfile: mask to be used with the right spatial resolution
%   e.g. 'std_masks/MNI152_T1_2mm_brain'
% centermaps: whether to center the maps according to the across-map average
%       (default: 0)
% scalemaps: whether to scale the maps so that each voxel has variance
%       equal 1 across maps; (default: 0)
% partialcorr: whether to use a partial correlation matrix or a correlation
%   matrix (default: 0)
% threshold: proportion threshold above which graph connections are
%       displayed (between 0 and 1, the higher the fewer displayed connections)
% outputfile: where to put things (do not indicate extension)
%   e.g. 'my_directory/maps'
% maskfile: if using NIFTI, mask to be used 
%   e.g. 'std_masks/MNI152_T1_2mm_brain'
%
% OUTPUT:
% graph: (voxels by voxels by state) array with the estimated connectivity maps
%
% Notes: need to have OSL in path
%
% Diego Vidaurre (2020)

if nargin < 4 || isempty(centergraphs), centergraphs = 0; end
if nargin < 5 || isempty(scalegraphs), scalegraphs = 0; end
if nargin < 6 || isempty(partialcorr), partialcorr = 0; end
if nargin < 7 || isempty(threshold), threshold = 0.95; end
if nargin < 8 || isempty(outputfile), outputfile = []; end


do_HMM_pca = strcmpi(hmm.train.covtype,'pca');
if ~do_HMM_pca && ~strcmp(hmm.train.covtype,'full')
    error('Cannot great a brain graph because the states do not contain any functional connectivity')
end

if strcmp(parcellation_file(end-11:end),'dtseries.nii')
    error('Cannot make a brain graph on surface space right now...')
elseif ~strcmp(parcellation_file(end-5:end),'nii.gz')
    error('Incorrect format: parcellation must have dtseries.nii or nii.gz extension')
end

NIFTI = parcellation(parcellation_file);
spatialMap = NIFTI.to_matrix(NIFTI.weight_mask); % voxels x components/parcels
try
    mni_coords = find_ROI_centres_2(spatialMap, maskfile, 0); % adapted from OSL
catch
    error('Error with OSL: find_ROI_centres in path?')
end   
ndim = size(spatialMap,2); K = length(hmm.state);
graphs = zeros(ndim,ndim,K);
edgeLims = [4 8]; colorLims = [0.1 1.1]; sphereCols = repmat([30 144 255]/255, ndim, 1);

for k = 1:K
    if partialcorr
        [~,~,~,C] = getFuncConn(hmm,k,1);
    else
        [~,C] = getFuncConn(hmm,k,1);
    end
    C(eye(ndim)==1) = 0;
    graphs(:,:,k) = C;
end

if centergraphs
    graphs = graphs - repmat(mean(graphs,3),[1 1 K]);
end
if scalegraphs
    graphs = graphs ./ repmat(std(graphs,[],3),[1 1 K]);
end

for k = 1:K
    C = graphs(:,:,k);
    %c = C(triu(true(ndim),1)==1); c = sort(c); c = c(end-1:-1:1); 
    %th = c(round(length(c)*(1-threshold))); 
    %C(C<th) = NaN; 
    figure(k+100);
    osl_braingraph(C, colorLims, repmat(0.5,ndim,1), [0.1 1.1], mni_coords, ...
        [], 100*threshold, sphereCols, edgeLims);
    colorbar off
    if ~isempty(outputfile)
        saveas(gcf,[outputfile '_' num2str(k) '.png'])
    end
    %fig_handle = gcf;
end

end


function coords = find_ROI_centres_2(spatialMap, brainMaskName, isBinary)
% based on the OSL's find_ROI_centres
[nVoxels, nParcels] = size(spatialMap);
MNIcoords     = osl_mnimask2mnicoords(brainMaskName);
assert(ROInets.rows(MNIcoords) == nVoxels);
for iParcel = nParcels:-1:1
    map = spatialMap(:, iParcel);
    % find ROI
    if isBinary
        cutOff = 0;
    else
        % extract top 5% of values
        cutOff = prctile(map, 95);
    end%if
    ROIinds = (map > cutOff);
    % find weightings
    if isBinary
        masses = ones(sum(ROIinds), 1);
    else
        masses = map(ROIinds);
    end
    % find CoM
    CoM = (masses' * MNIcoords(ROIinds,:)) ./ sum(masses);
    coords(iParcel, :) = CoM;
end
end

