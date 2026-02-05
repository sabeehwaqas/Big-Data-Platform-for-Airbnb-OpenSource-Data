# This is a deployment/installation guide

It is a free form. you can use it to explain how to deploy/install and run your code. Note that this deployment/installation guide ONLY helps to run your assignment. **It is not where you answer your solution for the assignment questions**

install python preferrable version 3.12 or higher
install terraform
install cassandra-driver
isntall gcloud
setup google cloud account
setup google project
change the project name in the main.tf file
grant IAM acces to terraform
create google cloud key and put it as creds.json ./MyBigDataProj/Big-Data-Platform-Asg-1/terraform/creds.json
enter the terraform folder and execute the terraform apply command please wait 5 min evena fter Apply complete! shows in terminal
opne google cloud and go to the google cloud sotrange , you will see mysimbdp-landing bucket
put the source data int the landing/raw folder (you can find the sample data at ./MyBigDataProj/assignment-1-103704559/data )
open initiate.py (path is ./MyBigDataProj/Big-Data-Platform-Asg-1/initiate.py) change the IP address of the cassandra node and execute the intiate.py it contains the schema for the cassandra nodes
now go to the nifi_piblic_ip address( you can find it formt he output of terraform scurpt when run successult)
https://<IP address>:8443/nifi/#/
now sign in into nifi the username is "sabeeh" and password is "sabeehsabeeh"
now click on process gorup icon from top and then click on import icon on the right side of the name dialog box.
go to the ./MyBigDataProj/Nifi Arch /DataIngest.json. you can now see the process loaded.
double click to enter the process
now double click on putdatabase process
you can see the Database Connection Pooling Service DBCPConnectionPool , click ont he 3 dots and click on go to
service, now enable all the services by clickign all the 3 dots for each and clcikign enable. then return to the prcoess by clking on the back to process on top left
ont he right side click start to run the pipeline
note: ignore the error on "PutDatabaseRecord Routing to failure.: java.lang.NullPointerException" as its the file issue . its been already handled by the pipeline by removing the corrupt rows to failed folder of cloud storage.

now you can see the data int eh cassadnar node by cqlsh from the terminal tothe the IP
liek this cslsh <IP addres> <9042>
