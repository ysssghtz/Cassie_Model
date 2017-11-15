function ExportKinematics_IMU_Cov(obj, export_function, export_path)
% Computes the Forward Kinematics Covariance Matrix (IMU to contact)
%
%   Author: Ross Hartley
%   Date:   11/15/2017
%
% Encoder Vector
encoders = SymVariable(obj.States.x(7:end));

% Left Foot Contact Frame
joints = obj.Joints(7:13);
joint_frames = cell(1,length(joints));
for i = 1:length(joints)
    joint_frames{i} = CoordinateFrame(...
        'Name',joints(i).Name,...
        'Reference',joints(i),...
        'Offset',[0, 0, 0],...
        'R',[0, 0, 0]);
end

frames = {obj.OtherPoints.VectorNav, joint_frames{:}, obj.ContactPoints.LeftToeBottom};
[Sigma_I1L, Q_I1L, S_I1L, Sigma_dagger_I1L] = Compute_FK_Covariance(frames, obj.States.x);

frames = {obj.OtherPoints.MultisenseAccelerometerFrame, joint_frames{:}, obj.ContactPoints.LeftToeBottom};
[Sigma_I2L, Q_I2L, S_I2L, Sigma_dagger_I2L] = Compute_FK_Covariance(frames, obj.States.x);

% Right Foot Contact Frame
joints = obj.Joints(14:end);
joint_frames = cell(1,length(joints));
for i = 1:length(joints)
    joint_frames{i} = CoordinateFrame(...
        'Name',joints(i).Name,...
        'Reference',joints(i),...
        'Offset',[0, 0, 0],...
        'R',[0, 0, 0]);
end

frames = {obj.OtherPoints.VectorNav, joint_frames{:}, obj.ContactPoints.RightToeBottom};
[Sigma_I1R, Q_I1R, S_I1R, Sigma_dagger_I1R] = Compute_FK_Covariance(frames, obj.States.x);

frames = {obj.OtherPoints.MultisenseAccelerometerFrame, joint_frames{:}, obj.ContactPoints.RightToeBottom};
[Sigma_I2R, Q_I2R, S_I2R, Sigma_dagger_I2R] = Compute_FK_Covariance(frames, obj.States.x);

% Export
N = length(frames)-1;
sigmas = SymVariable('sigma', [N-1,1]);

export_function(Sigma_I1L, 'Sigma_VectorNav_to_LeftToeBottom', export_path, {encoders, sigmas});
export_function(Q_I1L, 'Q_VectorNav_to_LeftToeBottom', export_path, {encoders, sigmas});
export_function(S_I1L, 'S_VectorNav_to_LeftToeBottom', export_path, {encoders, sigmas});
export_function(Sigma_dagger_I1L, 'Sigma_dagger_VectorNav_to_LeftToeBottom', export_path, {encoders, sigmas});

export_function(Sigma_I1R, 'Sigma_VectorNav_to_RightToeBottom', export_path, {encoders, sigmas});
export_function(Q_I1R, 'Q_VectorNav_to_RightToeBottom', export_path, {encoders, sigmas});
export_function(S_I1R, 'S_VectorNav_to_RightToeBottom', export_path, {encoders, sigmas});
export_function(Sigma_dagger_I1R, 'Sigma_dagger_VectorNav_to_RightToeBottom', export_path, {encoders, sigmas});

export_function(Sigma_I2L, 'Sigma_MultisenseIMU_to_LeftToeBottom', export_path, {encoders, sigmas});
export_function(Q_I2L, 'Q_MultisenseIMU_to_LeftToeBottom', export_path, {encoders, sigmas});
export_function(S_I2L, 'S_MultisenseIMU_to_LeftToeBottom', export_path, {encoders, sigmas});
export_function(Sigma_dagger_I2L, 'Sigma_dagger_MultisenseIMU_to_LeftToeBottom', export_path, {encoders, sigmas});

export_function(Sigma_I2R, 'Sigma_MultisenseIMU_to_RightToeBottom', export_path, {encoders, sigmas});
export_function(Q_I2R, 'Q_MultisenseIMU_to_RightToeBottom', export_path, {encoders, sigmas});
export_function(S_I2R, 'S_MultisenseIMU_to_RightToeBottom', export_path, {encoders, sigmas});
export_function(Sigma_dagger_I2R, 'Sigma_dagger_MultisenseIMU_to_RightToeBottom', export_path, {encoders, sigmas});

end


function [ Sigma, Q, S, Sigma_dagger] = Compute_FK_Covariance( frames, x )
% Computes covariance matrix for rotational/translational noise
%   
%   Author: Ross Hartley
%   Date:   11/14/2017
%   

N = length(frames)-1;
sigmas = SymVariable('sigma', [N-1,1]);

H1 = frames{1}.computeForwardKinematics;
HN1 = frames{N+1}.computeForwardKinematics;
A1 = H1(1:3,1:3);
AN1 = HN1(1:3,1:3);
A1N1 = A1'*AN1;

for i = 1:(N-1)
    Hi1 = frames{i+1}.computeForwardKinematics;
    sigma_i_dagger = frames{i+1}.Reference.Axis' * sigmas(i);
    A1i1 = A1'*Hi1(1:3,1:3); % Rotation from 1 to i+1
    AiN1 = A1i1'*A1N1;       % Rotation from i+1 to N+1 (Contact)
    
    for n = i:(N-1)
        Hn1 = frames{n+1}.computeForwardKinematics;
        Hn2 = frames{n+2}.computeForwardKinematics;
        Hn1n2 = Hn1\Hn2;
        tn1 = Hn1n2(1:3,end); 
        tn1 = subs(tn1, x, zeros(20,1)); % Should be a constant
        
        % Translation from n to n + 1
        A1n1 = A1'*Hn1(1:3,1:3); % Rotation from 1 to n+1
        Ai1n1 = A1i1'*A1n1;      % Rotation from i+1 to n+1
        % Compute Sum
        if n == i
            Si_sum = A1n1*Angles.skew(tn1)*Ai1n1';
        else
            Si_sum = Si_sum + A1n1*Angles.skew(tn1)*Ai1n1';
        end
    end

    % Build Covariance Matrix
    if i == 1
        Q = AiN1(1:3,1:3)';
        S = -Si_sum;
        sigma_dagger = sigma_i_dagger;
    else
        Q = [Q, AiN1(1:3,1:3)'];
        S = [S, -Si_sum];
        sigma_dagger = [sigma_dagger; sigma_i_dagger];
    end
end
Q = subs(Q, x(1:6), zeros(6,1));  
S = subs(S, x(1:6), zeros(6,1)); 
Sigma_dagger = diag(sigma_dagger);
Sigma = [Q; S] * Sigma_dagger * [Q; S].';

end