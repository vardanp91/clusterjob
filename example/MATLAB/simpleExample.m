% this is a Matlab script for testing 
% cj parrun, reduce commands.
% Author: Hatef Monajemi June 28 2016

file = 'results.txt';

for i = 1:3
	for j = 1:5	
				% write to a text file for testing reduce 	        
		        fid = fopen(file,'at');
		        fprintf(fid, '%i,%i,%i\n', i,j,i+j);
		        fclose(fid)
	end
end
													
	