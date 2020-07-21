for i in `cat files.txt`; 
do 
  wget "${HOST}/${i}"; 
done
