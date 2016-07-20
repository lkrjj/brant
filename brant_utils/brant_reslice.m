function brant_reslice(ref_file, src_file, prefix)
% ref_file: reference, cell or string
% src_file: source files, cell array or string. NOTE: the source files
% should only be 3D files or cell array of 3D files
% prefix: prefix of output files

if iscell(ref_file)
    ref_file = ref_file{1};
end

if strcmpi(ref_file(end-2:end), '.gz')
    pth = fileparts(ref_file);
    tmp_ref = load_untouch_nii_mod(ref_file, 1);
    ref_file = fullfile(pth, ['first_vol_', ref_file(1:end-3)]);
    save_untouch_nii(tmp_ref, ref_file);
end

if ischar(src_file)
    src_file = {src_file};
end

tmp_vol = spm_vol(ref_file);
if numel(tmp_vol) > 1
    add_str = ',1';
else
    add_str = '';
end

for m = 1:numel(src_file)
    gz_ind = 0;
    if strcmpi(src_file{m}(end-2:end), '.gz')
        gz_ind = 1;
        tmpDir = tempname;
        mkdir(tmpDir);
        pth = fileparts(src_file{m});
        if isempty(pth)
            pth = pwd;
        end
        src_file(m) = gunzip(src_file{m}, tmpDir);
    end
    
    job.ref = {[ref_file, add_str]};
    job.source = src_file(m);
    job.roptions.interp = 0; % 0 is nearest neighbour, 4 is 4th degree B-spline
    job.roptions.mask = 0;
    job.roptions.wrap = [0, 0, 0];
    job.roptions.prefix = prefix;
    
    if strcmpi(spm('ver'), 'SPM12')
        out = spm_run_coreg(job);
    else
        out = spm_run_coreg_reslice(job);
    end
    
    if gz_ind == 1
        if strcmpi(out.rfiles{1}(end-1:end), ',1')
            gzip(out.rfiles{1}(1:end-2), pth);
        else
            gzip(out.rfiles{1}, pth);
        end
        rmdir(tmpDir, 's');
    end
end