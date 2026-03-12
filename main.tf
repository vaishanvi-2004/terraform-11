provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "my-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1"

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "my-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_security_group" "public_sg" {
  name   = "my-sg"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow http port"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow port https"
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow sql"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public-sg"
  }
}
resource "aws_security_group" "private_sg" {
  name   = "private-sg"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    description     = "SSH from public instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-sg"
  }
}
resource "aws_instance" "public_instance" {
  ami                         = "ami-0f559c3642608c138"
  instance_type               = "t2.micro"
  key_name = "north"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.public_sg.id]
  user_data = <<-EOF
#!/bin/bash
yum install java -y
sleep 30
curl -O https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.115/bin/apache-tomcat-9.0.115.tar.gz
tar -xzvf apache-tomcat-9.0.115.tar.gz -C /opt
chmod +x /opt/apache-tomcat-9.0.115/bin/*.sh
cd /opt/apache-tomcat-9.0.115/webapps/
curl -O https://s3-us-west-2.amazonaws.com/studentapi-cit/student.war
/opt/apache-tomcat-9.0.115/bin/catalina.sh start
curl -O https://s3-us-west-2.amazonaws.com/studentapi-cit/mysql-connector.jar
FILE="/opt/tomcat-9.0.115/conf/context.xml"
    sed -i '$i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="500" maxIdle="30" maxWaitMillis="1000" username="shubham" password="Shubham21" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://${aws_db_instance.my_db.endpoint}/studentapp?useUnicode=yes&characterEncoding=utf8"/>' $FILE
    /opt/apache-tomcat-9.0.115/bin/./catalina.sh stop
    /opt/apache-tomcat-9.0.115/bin/./catalina.sh start
 
EOF

  tags = {
    Name = "public-instance"
  }
}

resource "aws_instance" "private_instance" {
  ami                    = "ami-0f559c3642608c138"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  tags = {
    Name = "private-instance"
  }
}
resource "aws_db_subnet_group" "my_db_subnet_group" {
  name = "my-db-subnet-group"

  subnet_ids = [
                 aws_subnet.private_subnet.id,
                 aws_subnet.public_subnet.id
                 ]
              
  tags = {
    Name = "my-db-subnet-group"
  }
}
resource "aws_db_instance" "my_db" {

  identifier = "mariadb-instance"

  allocated_storage = 10
  storage_type      = "gp2"

  engine         = "mariadb"
  engine_version = "10.6"

  instance_class = "db.t4g.micro"

  db_name  = "mydatabase"
  username = "vaishnavi"
  password = "vaishnavi17"

  db_subnet_group_name   = aws_db_subnet_group.my_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]

  publicly_accessible = true
  skip_final_snapshot = true
}

resource "aws_instance" "db_instance" {
  ami                    = "ami-0f559c3642608c138"
  instance_type          = "t3.micro"
  key_name = "north"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  tags = {
    Name = "rds-instance"
  }
  user_data = <<-EOF
  #!/bin/bash
  yum install mariadb105* -y
  systemctl start mariadb
  systemctl enable mariadb
  mysql -h {aws_db_instance.my_db.endpoint} -u vaishnavi -p vaishnavi17 <<'MYSQL
create database studentapp;
    use studentapp;
    CREATE TABLE if not exists students(student_id INT NOT NULL AUTO_INCREMENT,
	  student_name VARCHAR(100) NOT NULL,
    student_addr VARCHAR(100) NOT NULL,
  	student_age VARCHAR(3) NOT NULL,
	  student_qual VARCHAR(20) NOT NULL,
	  student_percent VARCHAR(10) NOT NULL,
  	student_year_passed VARCHAR(10) NOT NULL,
	  PRIMARY KEY (student_id)
	  );
    MYSQL;
    EOF

}
