function [cameraParams] = estimateSingleCameraParameters(imagePoints, boardSize, patchSize, imageSize)
% This function will estimate camera parameters (intrinsic, extrinsic) from
% checkerboard image points.

% Zhang's method consists of 5 parts
% 1. Estimate homography from checkerboard plane to screen space.
% 2. Calculate B matrix by solving Vb = 0.
% 3. Extract intrinsic parameters from B matrix.
% 4. Calculate extrinsic parameters from intrinsic parameters and homography.
% 5. Refine parameters using the maximum likelihood estimation.

% Function inputs:
% - 'imagePoints': positions of checkerboard points in a screen space.
% - 'boardSize': the number of horizontal, vertical patchs in the checkerboard.
% - 'patchSize': the size of the checkerboard patch in mm.
% - 'imageSize': the size of the checkerboard image in pixels.

% Function outputs:
% - 'cameraParams': a camera parameter includes intrinsic and extrinsic.

numView = size(imagePoints, 3);
numVerticalPatch = boardSize(1) - 1;
numHorizontalPatch = boardSize(2) - 1;
numCorner = size(imagePoints, 1);

%% Estimate a homography (appendix A)
% Generate checkerboard world points
worldPoints = zeros(size(imagePoints,1), size(imagePoints,2));

% Fill worldPoints (positions of checkerboard corners)
% ----- Your code here (1) ----- (slide 6)

for v = 1:numVerticalPatch
    for h = 1:numHorizontalPatch
        worldPoints((h-1)*numVerticalPatch+v,:) = patchSize*[h v];
    end
end

fprintf('finish (1)\n');

% Build L matrix
L = zeros(2 * numCorner, 9, numView);

% Fill L matrix
% ----- Your code here (2) ----- (slide 13)
for nv=1:numView
    for c=1:numCorner
        X = worldPoints(c,1);
        Y = worldPoints(c,2);
        u = imagePoints(c,1,nv);
        v = imagePoints(c,2,nv);
        L(c*2-1, :, nv)=[-X -Y -1 0 0 0 u*X u*Y u];
        L(c*2, :, nv)=[0 0 0 -X -Y -1 v*X v*Y v];
    end
end
fprintf('finish (2)\n');

% Calculate a homography using SVD
homography = zeros(3,3,numView);

% Fill homography matrix
% ----- Your code here (3) ----- (slide 15)
svdU = zeros(size(L,2),size(L,2),numView);
svdS = zeros(size(L,2),size(L,2),numView);
svdV = zeros(size(L,2),size(L,2),numView);

for nv=1:numView
    [svdU(:,:,nv),svdS(:,:,nv),svdV(:,:,nv)]=svd(L(:,:,nv).'*L(:,:,nv));
end

for nv=1:numView
    h = svdV(:,9,nv);
%     homography(:,:,nv) = [h(1) h(2) h(3); h(4) h(5) h(6); h(7) h(8) h(9)]/h(9);
    homography(:,:,nv) = [h(1) h(2) h(3); h(4) h(5) h(6); h(7) h(8) h(9)];
end

fprintf('finish (3)\n');

%% Solve closed-form (section 3.1)
V = zeros(2 * numView, 6);
b = zeros(6, 1);

% Fill V matrix and calculate b vector
% ----- Your code here (4) ----- (slide 19, 23)

for nv=1:numView
    h = homography(:,:,nv);
    v = zeros(2,2,6);
    for k=1:2
        for l=1:2
            v(k,l,1) = h(1,k)*h(1,l);
            v(k,l,2) = h(1,k)*h(2,l) + h(2,k)*h(1,l);
            v(k,l,3) = h(1,k)*h(3,l) + h(3,k)*h(1,l);
            v(k,l,4) = h(2,k)*h(2,l);
            v(k,l,5) = h(2,k)*h(3,l) + h(3,k)*h(2,l);
            v(k,l,6) = h(3,k)*h(3,l);
        end
    end
    
    V(2*nv-1,:) = v(1,2,:);
    V(2*nv,:) = (v(1,1,:)-v(2,2,:));
end

[svdU,svdS,svdV] = svd(V.'*V);
b = svdV(:,6);

fprintf('finish (4)\n');

%% Extraction of the intrinsic parameters from matrix B (appendix B)

% ----- Your code here (5) ----- (slide 24)
B = [b(1) b(2) b(3)
     b(2) b(4) b(5)
     b(3) b(5) b(6)];

v0 = (B(1,2)*B(1,3)-B(1,1)*B(2,3))/(B(1,1)*B(2,2)-B(1,2)*B(1,2));  % modify this line
lambda = B(3,3)-(B(1,3)*B(1,3)+v0*(B(1,2)*B(1,3)-B(1,1)*B(2,3)))/B(1,1);  % modify this line
alpha = sqrt(lambda/B(1,1));  % modify this line
beta = sqrt(lambda*B(1,1)/(B(1,1)*B(2,2)-B(1,2)*B(1,2)));  % modify this line
gamma = -B(1,2)*alpha*alpha*beta/lambda;  % modify this line
u0 = (gamma*v0/beta)-(B(1,3)*alpha*alpha/lambda);  % modify this line

K = [alpha gamma u0; 0 beta v0; 0 0 1];

fprintf('finish (5)\n');

%% Estimate initial RT (section 3.1)
Rt = zeros(3, 4, numView);

% Fill Rt matrix
% ----- Your code here (6) ----- (slide 25, 26)

for nv=1:numView
    gammap = (1/norm(K\homography(:,1,nv))+1/norm(K\homography(:,2,nv)))/2;
    Rt(:,1,nv) = gammap*(K\homography(:,1,nv));
    Rt(:,2,nv) = gammap*(K\homography(:,2,nv));
    Rt(:,3,nv) = cross(Rt(:,1,nv),Rt(:,2,nv));
    Rt(:,4,nv) = gammap*(K\homography(:,3,nv));
end

fprintf('finish (6)\n');

%% Maximum likelihood estimation (section 3.2)
options = optimoptions(@lsqnonlin, 'Algorithm', 'levenberg-marquardt', ...
    'TolX', 1e-32, 'TolFun', 1e-32, 'MaxFunEvals', 1e64, ...
    'MaxIter', 1e64, 'UseParallel', true);

% Build initial x value as x0
% ----- Your code here (7) ----- (slide 29)

Rp = zeros(3,3,numView);

for nv=1:numView
    [svdU,svdS,svdV] = svd(Rt(:,1:3,nv));
    Rp(:,:,nv) = svdU*svdV.';
end


% 5 for intrinsic
% 3 for translation, 3 for rotation, total 6 for each checkerboard image
x0 = zeros(5 + 6 * size(imagePoints, 3), 1);  % modify this line

x0(1:5,1) = [alpha; beta; gamma; u0; v0];
for nv=1:numView
    rotationVec = rotationMatrixToVector(Rp(:,:,nv).');
    x0(6*nv:6*nv+5,1)=[rotationVec.'; Rt(:,4,nv)];
end

fprintf('finish (7)\n');

% Non-least square optimization
% Read [https://mathworks.com/help/optim/ug/lsqnonlin.html] for more information
[objective] = @(x) func_calibration(imagePoints, worldPoints, x);

[x_hat, ~, ~, ~, ~] = lsqnonlin(objective,x0,[],[],options);

%% Build camera parameters
rvecs = zeros(numView, 3);
tvecs = zeros(numView, 3);
K = [1, 0, 0
     0, 1, 0
     0, 0, 1];

% Extract intrinsic matrix K, rotation vectors and translation vectors from x_hat
% ----- Your code here (8) -----

alpha = x_hat(1,1);
beta = x_hat(2,1);
gamma = x_hat(3,1);
u0 = x_hat(4,1);
v0 = x_hat(5,1);
K = [alpha gamma u0
     0 beta v0
     0 0 1];

for nv=1:numView
    rvecs(nv,:) = x_hat(6*nv:6*nv+2,1);
    tvecs(nv,:) = x_hat(6*nv+3:6*nv+5,1);
end


% Generate cameraParameters structure
cameraParams = cameraParameters('IntrinsicMatrix', K', ...
    'RotationVectors', rvecs, 'TranslationVectors', tvecs, ...
    'WorldPoints', worldPoints, 'WorldUnits', 'mm', ...
    'imageSize', imageSize) ; 


reprojected_errors = zeros(size(imagePoints));

% Uncomment this line after you implement this function to calculate
% reprojection errors of your camera parameters.
reprojected_errors = imagePoints - cameraParams.ReprojectedPoints;

cameraParams = cameraParameters('IntrinsicMatrix', K', ...
    'RotationVectors', rvecs, 'TranslationVectors', tvecs, ...
    'WorldPoints', worldPoints, 'WorldUnits', 'mm', ...
    'imageSize', imageSize, 'ReprojectionErrors', reprojected_errors) ; 