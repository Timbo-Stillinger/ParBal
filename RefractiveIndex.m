function [ N, varargout] = RefractiveIndex( wave, substance, varargin )
% [ N [, wavelengths] ] = RefractiveIndex( wave, substance [, units] )
% complex refractive index of ice or water, simple dust and soot
%
% INPUT
%   wave - wavelength(s), default in um (if empty, return values from
%   table)
%   substance - either 'ice' or 'snow' (same), 'water', 'dust', or 'soot'
%
% OPTIONAL INPUT
%   units for wavelength, default 'um', but 'nm', 'mum', 'mm', 'cm', 'm', 'GHz'
%       are supported
%
% OUTPUT
%   N - complex refractive index (imaginary part positive for input to calcmie)
% OPTIONAL OUTPUT
%   wavelengths - wavelengths from original database

% DATA SOURCES
% ice - Warren, S.G., & Brandt, R.E. (2008). Optical constants of ice from
% the ultraviolet to the microwave: A revised compilation. JGR, 113, D14220.
% doi:10.1029/2007JD009744
% data from https://atmos.washington.edu/ice_optical_constants/
% with some values in the visible/UV wavelengths corrected with
% measurements from
% Picard, G., Libois, Q., & Arnaud, L. (2016). Refinement of the ice
% absorption spectrum in the visible using radiance profile measurements in
% Antarctic snow. The Cryosphere, 10(6), 2655-2672. doi:10.5194/tc-10-2655-2016
% data from http://lgge.osug.fr/~picard/ice_absorption/
%
% water - Hale, G.M., & Querry, M.R. (1973). Optical constants of water in
% the 200-nm to 200-�m wavelength region. Applied Optics, 12(3), 555-563.
% doi:10.1364/AO.12.000555

% method - for ice and water real parts against log wave, log imag parts
% against log wave
% for dust and soot, real and imaginary parts against wave

numarg = 2;
narginchk(numarg,3)
nargoutchk(0,2)

persistent already pr_ice pi_ice pr_water pi_water minmaxIce minmaxWater

method = 'makima';
extrap = 'nearest';

% 1st pass, calculate the interpolation functions
if isempty(already) || ~already
    already = true;
    m = matfile('IndexRefraction.mat');
    [wvice,ice] = correctIceRefractive('ice_refractive_picard2016.mat',m.wvice,m.ice);
    [wvwater,water] = correctWaterRefractive(m.wvwater,m.water);
    logWice = log(wvice);
    logWwater = log(wvwater);
    % functions for pchip interpolation, with nearest neighbor extrapolation
    pr_ice = griddedInterpolant(logWice,ice(:,1),method,extrap);
    pi_ice = griddedInterpolant(logWice,log(ice(:,2)),method,extrap);
    pr_water = griddedInterpolant(logWwater,water(:,1),method,extrap);
    pi_water = griddedInterpolant(logWwater,log(water(:,2)),method,extrap);
    minmaxIce = [min(pr_ice.GridVectors{1}) max(pr_ice.GridVectors{1})];
    minmaxWater = [min(pr_water.GridVectors{1}) max(pr_water.GridVectors{1})];
end

substance = lower(substance);
if ~isempty(wave)
    % wavelength in correct units if argument specified different than um
    if nargin>numarg
        wave = convertUnits(wave,varargin{1},'um');
    end
    logWave = log(wave);
    
elseif strcmp(substance,'ice') || strcmp(substance,'snow')
    logWave = pr_ice.GridVectors{1};
    wave = exp(logWave);
elseif strcmp(substance,'water')
    logWave = pr_water.GridVectors{1};
    wave = exp(logWave);
else
    error('wave (first arg) cannot be empty for dust or soot')
end

% all passes, do the interpolation
% if wave is a matrix, need to vectorize and then reshape results
waveSize = size(wave);
wave = wave(:);
if exist('logWave','var')
    logWave = logWave(:);
end

% interpolation depending on substance
switch substance
    case {'ice','snow'}
        if any(logWave(:)<minmaxIce(1)) || any(logWave(:)>minmaxIce(2))
            warning('some wavelengths outside range of ice interpolation, nearest values used')
        end
        realpart = pr_ice(logWave);
        imagpart = exp(pi_ice(logWave));
    case 'water'
        if any(logWave(:)<minmaxWater(1)) || any(logWave(:)>minmaxWater(2))
            warning('some wavelengths outside range of water interpolation, nearest values used')
        end
        realpart = pr_water(logWave);
        imagpart = exp(pi_water(logWave));
    case 'dust'
        [realpart,imagpart] = dustRefractive(wave);
    case 'soot'
        [realpart,imagpart] = sootRefractive(wave);
    otherwise
        error('substance ''%s'' not recognized',substance)
end

N = complex(realpart,abs(imagpart));
if ~isequal(size(N),waveSize)
    N = reshape(N,waveSize);
end

% convert wavelengths returned if specified
if nargout>1
    if nargin<3
        varargout{1} = wave;
    else
        varargout{1} = convertUnits(wave,'um',varargin{1});
    end
end
end

function [n,k] = dustRefractive(lambda)
persistent dustAlready DI
if isempty(dustAlready)
    dustAlready = true;
    % data mostly from Skiles et al 2016, J Glac, doi 10.1017/jog.2016.126
    % and from Zender  http://dust.ess.uci.edu/smn/smn_cgd_200610.pdf
    % columns: wavelength (um), imag part, weight
    dustData = [0.35 0.0015 1; 0.40 0.0013 1; 0.45 0.0011 1; 0.50 0.0010 1;...
        0.55 0.0008 1; 0.60 0.0006 1; 0.65 0.0007 1; 0.70 0.0006 1;...
        0.75 0.0006 1; 0.80 0.0006 1; 0.90 0.0006 1; 1.00 0.0006 1;...
        1.10 0.0005 1; 1.20 0.0005 1; 1.30 0.0005 1; 1.40 0.0005 1;...
        1.50 0.0005 1; 0.30 0.0048 0.5; 0.35 0.0043 0.5; 0.40 0.0045 0.5;...
        0.45 0.0030 0.5; 0.50 0.0025 0.5; 0.55 0.0020 0.5; 0.60 0.0015 0.5;...
        0.65 0.0012 0.5; 0.70 0.0010 0.5; 0.75 0.0010 0.5; 0.80 0.0009 0.75;...
        0.90 0.0008 0.75; 1.00 0.0007 0.75; 1.10 0.0006 0.75; 1.80 0.0005 1;...
        1.90 0.0006 1; 2.00 0.0006 1; 2.10 0.0005 1; 2.20 0.0006 1;...
        2.30 0.0006 1; 2.40 0.0007 1; 2.50 0.0010 1];
    % smooth parameter from visual inspection of cftool results
    DI = fit(dustData(:,1),dustData(:,2),'smoothingspline',...
        'SmoothingParam',0.97,'Weights',dustData(:,3));
end
n = 1.55;
lambda(lambda<DI.p.breaks(1)) = DI.p.breaks(1);
lambda(lambda>DI.p.breaks(end)) = DI.p.breaks(end);
k = DI(lambda);
end

function [n,k] = sootRefractive(lambda)
% value from Bond, T.C., and R.W. Bergstrom (2006), Light absorption by
% carbonaceous particles: An investigative review, Aerosol Science and
% Technology, 40, 27-67, doi: 10.1080/02786820500421521.
n = repmat(1.95,size(lambda));
k = repmat(0.79,size(lambda));

end

function [waveIce, N] = correctIceRefractive(file,wvice,iceOrig)
% [waveIce, N] = correctIceRefractive(file,wvice,iceOrig)
%correct Warren-Brandt ice refractive index (imag part) with later
%measurements by Picard et al.
%adjuticate with smoothing spline
%
%Input
% file - with the Picard data, but in um
% wvice - wavelength, um
% iceOrig - complex index (real col 1, imag col 2)
%
%Output
% waveIce - consolidated wavelengths, um
% N - consolidated new refractive index (col 1 real, col 2 imaginary)

M = matfile(file); % file with the Picard data, convered to um

% smooth up to the largest Picard wavelength
k = find(wvice>max(M.wvPicard),1,'first');
x = [wvice(1:k); M.wvPicard];
y = [iceOrig(1:k,2); M.kicePicard];
Fi = fit(log(x),log(y),'smoothingspline','SmoothingParam',0.97);
x = unique(x);

% insert the new wavelength
waveIce = [x; wvice(k+1:end)];

% real part
Fr = fit(log(wvice),iceOrig(:,1),'smoothingspline','SmoothingParam',0.9999);
realrefractive = Fr(log(waveIce));

% smooth the whole imaginary part
F = fit(log(waveIce),[Fi(log(x)); log(iceOrig(k+1:end,2))],...
    'smoothingspline','SmoothingParam',0.9999);
newImag = exp(F(log(waveIce)));

% new refractive index
N = [realrefractive newImag];

end

function [waveWater, N] = correctWaterRefractive(wvwater,waterOrig)
% [waveWater, N] = correctWaterRefractive(wvwater,waterOrig)
%smooth refractive indices of water, from Hale & Querry 
%
%Input
% wvwater - wavelength, um
% waterOrig - complex index (real col 1, imag col 2)
%
%Output
% waveWater - consolidated wavelengths, um
% N - consolidated new refractive index (col 1 real, col 2 imaginary)

Fr = fit(log(wvwater),waterOrig(:,1),'smoothingspline','SmoothingParam',0.9999);
Fi = fit(log(wvwater),log(waterOrig(:,2)),'smoothingspline','SmoothingParam',0.9999);

waveWater = wvwater;
N = [Fr(log(waveWater)) exp(Fi(log(waveWater)))];

end