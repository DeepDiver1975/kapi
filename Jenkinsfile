#!/usr/bin/env groovy

pipeline {
	agent {
		docker {
			image 'golang:1.13.4-stretch' // Ensure to use old glibc, to be compatible to Debian 9
			args '-u 0'
		 }
	}
	environment {
		DEP_RELEASE_TAG = 'v0.5.4'
		GOBIN = '/usr/local/bin'
		DEBIAN_FRONTEND = 'noninteractive'
	}
	stages {
		stage('Bootstrap') {
			steps {
				echo 'Bootstrapping..'
				sh 'curl -sSL -o $GOBIN/dep https://github.com/golang/dep/releases/download/$DEP_RELEASE_TAG/dep-linux-amd64 && chmod 755 $GOBIN/dep'
				sh 'go get -v golang.org/x/lint/golint'
				sh 'go get -v github.com/tebeka/go2xunit'
				sh 'go get -v github.com/axw/gocov/...'
				sh 'go get -v github.com/AlekSi/gocov-xml'
				sh 'go get -v github.com/wadey/gocovmerge'
				sh 'apt-get update && apt-get install -y build-essential'
				sh 'go version'
			}
		}
		stage('Lint') {
			steps {
				echo 'Linting..'
				sh 'make lint | tee golint.txt || true'
				sh 'make vet | tee govet.txt || true'
			}
		}
		stage('Build') {
			steps {
				echo 'Building..'
				sh 'make'
				sh './bin/kapid version'
			}
		}
		stage('Test') {
			when {
				not {
					branch 'master'
				}
			}
			steps {
				echo 'Testing..'
				sh 'make test-xml-short'
			}
		}
		stage('Test with coverage') {
			when {
				branch 'master'
			}
			steps {
				echo 'Testing with coverage..'
				sh 'make test-coverage COVERAGE_DIR=test/coverage.jenkins'
				publishHTML([allowMissing: false, alwaysLinkToLastBuild: true, keepAll: true, reportDir: 'test/coverage.jenkins', reportFiles: 'coverage.html', reportName: 'Go Coverage Report HTML', reportTitles: ''])
				step([$class: 'CoberturaPublisher', autoUpdateHealth: false, autoUpdateStability: false, coberturaReportFile: 'test/coverage.jenkins/coverage.xml', failUnhealthy: false, failUnstable: false, maxNumberOfBuilds: 0, onlyStable: false, sourceEncoding: 'ASCII', zoomCoverageChart: false])
			}
		}
		stage('Dist') {
			steps {
				echo 'Dist..'
				sh 'test -z "$(git diff --shortstat 2>/dev/null |tail -n1)" && echo "Clean check passed."'
				sh 'make check'
				sh 'make dist'
			}
		}
	}
	post {
		always {
			archiveArtifacts 'dist/*.tar.gz'
			junit allowEmptyResults: true, testResults: 'test/*.xml'
			warnings parserConfigurations: [[parserName: 'Go Lint', pattern: 'golint.txt'], [parserName: 'Go Vet', pattern: 'govet.txt']], unstableTotalAll: '0'
			cleanWs()
		}
	}
}
