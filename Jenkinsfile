// Jenkinsfile - Automation Alchemy CI/CD pipeline.
//
// Jenkins checks GitHub every 2 minutes. For every new commit:
//   1. Version   - the short commit ID becomes the image tag (e.g. 3f2a1bc)
//   2. Build     - build the backend and frontend images
//   3. Push      - push them to Docker Hub + save build-info.txt as the build artifact
//   4. Deploy    - Ansible deploys the new tag: backend, then web servers one at a time
//   5. Smoke     - check through the load balancer that the new version is live
//
// Tests (Group 6) and rollback + notifications (Group 7) are added later.

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()                       // never two deploys at once
        buildDiscarder(logRotator(numToKeepStr: '20'))  // keep the last 20 builds
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        // Must match dockerhub_user in ansible/group_vars/all/vars.yml
        DOCKERHUB_USER      = 'zeek14'
        LB_URL              = 'http://192.168.56.10/'
        ANSIBLE_FORCE_COLOR = '1'
    }

    stages {
        stage('Version') {
            steps {
                script {
                    // Every image traces back to exactly one commit.
                    env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.IMAGE_TAG}"
                }
                sh 'git log -1 --format="Commit %h by %an: %s"'
            }
        }

        stage('Build images') {
            steps {
                sh '''
                    for component in backend frontend; do
                      docker build \
                        --build-arg APP_VERSION="$IMAGE_TAG" \
                        --tag "$DOCKERHUB_USER/alchemy-$component:$IMAGE_TAG" \
                        "app/$component"
                    done
                '''
            }
        }

        stage('Push to Docker Hub') {
            steps {
                // Jenkins hides these values in the log (shown as ****).
                withCredentials([usernamePassword(credentialsId: 'dockerhub',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_TOKEN')]) {
                    sh '''
                        echo "$DH_TOKEN" | docker login --username "$DH_USER" --password-stdin
                        for component in backend frontend; do
                          docker push "$DOCKERHUB_USER/alchemy-$component:$IMAGE_TAG"
                        done
                    '''
                }
                // The build artifact: which commit produced which exact images.
                sh '''
                    {
                      echo "version:  $IMAGE_TAG"
                      echo "commit:   $(git rev-parse HEAD)"
                      echo "built:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
                      echo "jenkins:  build #$BUILD_NUMBER"
                      for component in backend frontend; do
                        echo "$component: $(docker image inspect --format '{{index .RepoDigests 0}}' "$DOCKERHUB_USER/alchemy-$component:$IMAGE_TAG")"
                      done
                    } > build-info.txt
                    cat build-info.txt
                '''
                archiveArtifacts artifacts: 'build-info.txt', fingerprint: true
            }
        }

        stage('Deploy') {
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'ansible-ssh-key', keyFileVariable: 'SSH_KEY'),
                    file(credentialsId: 'ansible-vault-pass', variable: 'VAULT_PASS_FILE')
                ]) {
                    dir('ansible') {
                        // Same deploy.yml as the first deploy - only the tag is new.
                        sh '''
                            export ANSIBLE_PRIVATE_KEY_FILE="$SSH_KEY"
                            export ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PASS_FILE"
                            ansible-playbook deploy.yml -e image_tag="$IMAGE_TAG"
                        '''
                    }
                }
            }
        }

        stage('Smoke test') {
            steps {
                sh 'bash scripts/smoke-test.sh "$LB_URL" "$IMAGE_TAG"'
            }
        }
    }

    post {
        always {
            // Don't leave Docker Hub login details on the CI server.
            sh 'docker logout || true'
            // Remove leftover image layers so the disk doesn't fill up over time.
            sh 'docker image prune -f'
        }
        success {
            echo "Version ${env.IMAGE_TAG} is live: http://localhost:8080"
        }
        failure {
            echo "Pipeline FAILED - version ${env.IMAGE_TAG} is not (fully) deployed."
        }
    }
}

