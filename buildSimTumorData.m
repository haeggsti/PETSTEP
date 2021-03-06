function  [FWPTtrue,FWPTtrueB,FWTUtrue,FWPTscatter,FWTUscatter,FWPTrandoms,FWTUrandoms,FWAC,wcc,counts] = ...
    buildSimTumorData(tumorPT,refPT,muCT,psf,vox,countScale,SF,RF)
%"buildSimData"
%   Builds un-noised PET projection data and attenuation projections
%
% CRS, 08/01/2013
%
% Usage: 
%   [FWPTtrue,FWPTscatter,FWPTrandoms,FWAC,wcc] = buildSimData(refPT,ctMu,psf,radBin,vox.petSim.rtz(2),zSlice,voxXpt,voxXct,countsTotal,SF,RF)
%       refPT       = reference PET image w/ tumor
%       ctMuCT      = reference  CT image w/ tumor in cm^2/g
%       psf         = FWHM of PSF
%       radBin      = radial bins
%       vox.petSim.rtz(2)      = projection bins
%       zSlice      = number fof slices
%       voxXpt      = PET voxel Size
%       voxXct      =  CT voxel Size
%       countsTotal = mean total counts per slice
%       SF          = Scatter fraction
%       RF          = Randoms fraction
%
% Copyright 2010, Joseph O. Deasy, on behalf of the CERR development team.
% 
% This file is part of The Computational Environment for Radiotherapy Research (CERR).
% 
% CERR development has been led by:  Aditya Apte, Divya Khullar, James Alaly, and Joseph O. Deasy.
% 
% CERR has been financially supported by the US National Institutes of Health under multiple grants.
% 
% CERR is distributed under the terms of the Lesser GNU Public License. 
% 
%     This version of CERR is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
% 
% CERR is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
% without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
% See the GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with CERR.  If not, see <http://www.gnu.org/licenses/>.%
%
%% Builds un-noised data 

% rescale Images to simulation size
PTtrue = zeros(vox.petSim.nxn);
TUtrue = zeros(vox.petSim.nxn);
CTmu   = zeros(vox.petSim.nxn);
for i = 1:vox.petSim.nxn(3)
    
    TUmask =  tumorPT(:,:,i) - refPT(:,:,i);
    TUmask(TUmask > 0) = 1; TUmask(TUmask < 1) = 0; 
    PTtmp = refPT(:,:,i).*(1-TUmask);
    Tutmp = tumorPT(:,:,i).*TUmask;
    PTtrue(:,:,i) = imresize(PTtmp,vox.petSim.nxn(1:2),'cubic');
    TUtrue(:,:,i) = imresize(Tutmp,vox.petSim.nxn(1:2),'cubic');
    
    if (isempty(muCT))
        CTmu = [];
    else 
        % pad CT to match PET
        CTmuTmp0 = zeros(vox.petSim.nxn(1:2));
        CTmuTmp  = imresize(muCT(:,:,i),vox.ct.xyz(1)/vox.petSim.xyz(1),'cubic');
        
        xA = max(1,round(( vox.petSim.nxn(1) - size(CTmuTmp,2) )/2) + 1);
        xB = xA + size(CTmuTmp,2) - 1;
        yA = max(1,round(( vox.petSim.nxn(1) - size(CTmuTmp,1) )/2) + 1);
        yB = yA + size(CTmuTmp,1) - 1;
        
        CTmuTmp0(yA:yB,xA:xB) = CTmuTmp;
        CTmu(:,:,i) = imresize( CTmuTmp0,vox.petSim.nxn(1:2), 'cubic' );
    end
end
PTtrue(PTtrue < 0) = 0;
TUtrue(TUtrue < 0) = 0;
CTmu(CTmu < 0) = 0; % Alignment verified

% scale PET for counts
cntsPET = PTtrue; cntsPET(cntsPET <= 0.1) = 0; cntsPET(cntsPET > 0) = 1;
countsPET = countScale * vox.pet.vol/1000 * (vox.pet.nxn(1)/vox.petSim.nxn(1))^2 * ...
    sum(cntsPET(:));

%%  Blur Images w/ PSF
% Build blurring kernels
% PSF kernel
sigma = psf * vox.petSim.nxn(1) / vox.pet.fov(1);
sigMat = max( ceil(3*sigma) , 5 );
if (mod(sigMat,2) == 0), sigMat = sigMat + 1; end
PSF  = fspecial('gaussian', sigMat, sigma / ( 2*sqrt(2*log(2)) ) );

% scatter kernel
scatterFWHM = 200;
s_sigma = scatterFWHM * vox.petSim.nxn(1) / vox.pet.fov(1);
sigMat = max( ceil(3*s_sigma) , 3 );
if (mod(sigMat,2) == 0), sigMat = sigMat + 1; end
scatterK = fspecial('gaussian',sigMat, s_sigma / ( 2*sqrt(2*log(2)) ) );

% Blur images
PTscatter = zeros(size(PTtrue));
TUscatter = zeros(size(TUtrue));
for i = 1:vox.petSim.nxn(3)
    PTtrueB(:,:,i)   = imfilter(PTtrue(:,:,i),PSF,     'replicate','same','conv');
    TUtrue(:,:,i)    = imfilter(TUtrue(:,:,i),PSF,     'replicate','same','conv');
    CTmu(:,:,i)      = imfilter(CTmu(:,:,i),  PSF,     'replicate','same','conv');
    PTscatter(:,:,i) = imfilter(PTtrue(:,:,i),scatterK,'replicate','same','conv');
    TUscatter(:,:,i) = imfilter(TUtrue(:,:,i),scatterK,'replicate','same','conv');
end

%% Forward project images
PHI = 0:180/vox.petSim.rtz(2):180*(1-1/vox.petSim.rtz(2));
FWAC        = ones([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);
FWPTtrueNAC = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);
FWPTscatter = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);
FWPTrandoms = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);

FWPTtrueBNAC = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);
FWTUtrueNAC  = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);
FWTUscatter  = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);
FWTUrandoms  = zeros([vox.petSim.rtz(1) vox.petSim.rtz(2) vox.petSim.rtz(3)]);

for i = 1:vox.petSim.rtz(3)
    if (isempty(muCT))
        FWAC(:,:,i) = ones([vox.petSim.rtz(1) vox.petSim.rtz(2)]);
    else
        FWAC(:,:,i) = exp( -( vox.pet.xyz(1) * vox.pet.nxn(1) / vox.petSim.nxn(1) )/10 * ...
            radon( CTmu(:,:,i), PHI ) );
    end % Alignment verified
end    
FWAC(FWAC > 1) = 1;

for i = 1:vox.petSim.rtz(3)
    FWPTtrueNAC(:,:,i)  = radon( PTtrue(:,:,i),    PHI );
    FWPTtrueBNAC(:,:,i) = radon( PTtrueB(:,:,i),   PHI );
    FWPTscatter(:,:,i)  = radon( PTscatter(:,:,i), PHI );
    
    FWTUtrueNAC(:,:,i) = radon(TUtrue(:,:,i),PHI);
    FWTUscatter(:,:,i) = radon(TUscatter(:,:,i),PHI);
end
radA = floor( (vox.petSim.rtz(1) - vox.petSim.nxn(1))/2 ) + 1; radB = vox.petSim.rtz(1) - radA - 1;
FWPTrandoms(radA:radB,:,:) = 1;
FWPTtrue  = FWPTtrueNAC  .* FWAC;
FWPTtrueB = FWPTtrueBNAC .* FWAC;
FWTUtrue  = FWTUtrueNAC  .* FWAC;
FWTUrandoms(radA:radB,:,i) = 1; 


% Attenuate total counts
imageTCnts    = sum( FWPTtrue(:)    + FWTUtrue(:) );
imageTNACCnts = sum( FWPTtrueNAC(:) + FWTUtrueNAC(:) );
imageTCntsB   = sum( FWPTtrueB(:)   + FWTUtrue(:) );
imageSCnts    = sum( FWPTscatter(:) + FWTUscatter(:) );
imageRCnts    = sum( FWPTrandoms(:) + FWTUrandoms(:) );

countsTrue    = countsPET * imageTCntsB / imageTNACCnts;
countsScatter = SF/(1-SF) * countsTrue;
countsRandoms = RF/(1-RF) * (countsTrue + countsScatter);

wcc = countsTrue / imageTCnts;
wcc = wcc * (  vox.petSim.nxn(1) / vox.petOut.nxn(1) ); 

FWPTtrue    = countsTrue    * FWPTtrue    / imageTCnts;
FWPTtrueB   = countsTrue    * FWPTtrueB   / imageTCntsB;
FWPTscatter = countsScatter * FWPTscatter / imageSCnts;
FWPTrandoms = countsRandoms * FWPTrandoms / imageRCnts;

FWTUtrue    = countsTrue    * FWTUtrue    / imageTCntsB;
FWTUscatter = countsScatter * FWTUscatter / imageSCnts;
FWTUrandoms = countsRandoms * FWTUrandoms / imageRCnts;

counts.total   = countsTrue + countsScatter + countsRandoms;
counts.true    = countsTrue;
counts.scatter = countsScatter;
counts.randoms = countsRandoms;
counts.NEC     = counts.true^2 / counts.total;
counts.ID      = counts.NEC / prod(vox.petOut.nxn);

counts

end
