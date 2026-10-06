// Jenkinsfile - Group 4 placeholder.
// Proves the wiring: Jenkins sees the repo, and can use Docker and Ansible.
// Group 5 replaces this with the real pipeline (build -> push -> deploy).
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {
        stage('Show commit') {
            steps {
                sh 'git log -1 --oneline'
            }
        }
        stage('Check tools') {
            steps {
                sh 'docker version --format "Docker server {{.Server.Version}}"'
                sh 'ansible --version | head -1'
            }
        }
    }
}

