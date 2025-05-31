#!/usr/bin/env python3
"""
Ruuvi Home Setup File Generator
Generates configuration files, scripts, and services from templates
"""

import os
import sys
import yaml
import json
import argparse
import logging
from pathlib import Path
from typing import Dict, Any, List
from dataclasses import dataclass, asdict
from jinja2 import Environment, FileSystemLoader, Template

@dataclass
class GeneratorConfig:
    """Configuration for file generator"""
    ruuvi_user: str
    project_dir: str
    data_dir: str
    log_dir: str
    backup_dir: str
    webhook_port: int
    webhook_secret: str
    frontend_port: int
    api_port: int
    db_port: int
    db_user: str
    db_name: str
    mosquitto_port: int
    timezone: str
    python_venv: str
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'GeneratorConfig':
        """Create config from dictionary"""
        return cls(**{k: v for k, v in data.items() if k in cls.__annotations__})

class FileGenerator:
    """Handles file generation from templates"""
    
    def __init__(self, config: GeneratorConfig, template_dir: Path, output_dir: Path):
        self.config = config
        self.template_dir = template_dir
        self.output_dir = output_dir
        self.env = Environment(
            loader=FileSystemLoader(str(template_dir)),
            trim_blocks=True,
            lstrip_blocks=True
        )
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
    
    def generate_file(self, template_name: str, output_path: Path, 
                     extra_vars: Dict[str, Any] = None) -> bool:
        """Generate a single file from template"""
        try:
            template = self.env.get_template(template_name)
            
            # Merge config with extra variables
            template_vars = asdict(self.config)
            if extra_vars:
                template_vars.update(extra_vars)
            
            # Generate content
            content = template.render(**template_vars)
            
            # Ensure output directory exists
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Write file
            with open(output_path, 'w') as f:
                f.write(content)
            
            self.logger.info(f"Generated: {output_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to generate {output_path}: {e}")
            return False
    
    def set_file_permissions(self, file_path: Path, mode: int, 
                           owner: str = None) -> bool:
        """Set file permissions and ownership"""
        try:
            # Set file mode
            file_path.chmod(mode)
            
            # Set ownership if specified
            if owner:
                import pwd
                import grp
                user_info = pwd.getpwnam(owner)
                group_info = grp.getgrnam(owner)
                os.chown(file_path, user_info.pw_uid, group_info.gr_gid)
            
            return True
        except Exception as e:
            self.logger.error(f"Failed to set permissions for {file_path}: {e}")
            return False

class RuuviSetupGenerator:
    """Main generator for Ruuvi Home setup files"""
    
    def __init__(self, config_file: Path):
        self.config_file = config_file
        self.config = self._load_config()
        self.script_dir = Path(__file__).parent
        self.template_dir = self.script_dir / "templates"
        self.output_dir = Path(self.config.project_dir)
        
        self.generator = FileGenerator(
            self.config, 
            self.template_dir, 
            self.output_dir
        )
    
    def _load_config(self) -> GeneratorConfig:
        """Load configuration from file"""
        try:
            with open(self.config_file) as f:
                if self.config_file.suffix == '.yaml' or self.config_file.suffix == '.yml':
                    data = yaml.safe_load(f)
                else:
                    data = json.load(f)
            
            return GeneratorConfig.from_dict(data)
        except Exception as e:
            logging.error(f"Failed to load config: {e}")
            sys.exit(1)
    
    def generate_python_scripts(self) -> bool:
        """Generate Python scripts"""
        scripts = [
            {
                'template': 'webhook.py.j2',
                'output': 'scripts/deploy-webhook.py',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'health-check.py.j2',
                'output': 'scripts/health-check.py',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'database-manager.py.j2',
                'output': 'scripts/database-manager.py',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            }
        ]
        
        success = True
        for script in scripts:
            output_path = self.output_dir / script['output']
            if self.generator.generate_file(script['template'], output_path):
                self.generator.set_file_permissions(
                    output_path, 
                    script['mode'], 
                    script['owner']
                )
            else:
                success = False
        
        return success
    
    def generate_shell_scripts(self) -> bool:
        """Generate shell scripts"""
        scripts = [
            {
                'template': 'deploy.sh.j2',
                'output': 'scripts/deploy.sh',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'backup.sh.j2',
                'output': 'scripts/backup.sh',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'maintenance.sh.j2',
                'output': 'scripts/maintenance.sh',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'monitor.sh.j2',
                'output': 'scripts/monitor.sh',
                'mode': 0o755,
                'owner': self.config.ruuvi_user
            }
        ]
        
        success = True
        for script in scripts:
            output_path = self.output_dir / script['output']
            if self.generator.generate_file(script['template'], output_path):
                self.generator.set_file_permissions(
                    output_path, 
                    script['mode'], 
                    script['owner']
                )
            else:
                success = False
        
        return success
    
    def generate_systemd_services(self) -> bool:
        """Generate systemd service files"""
        services = [
            {
                'template': 'ruuvi-home.service.j2',
                'output': '/etc/systemd/system/ruuvi-home.service',
                'mode': 0o644,
                'owner': 'root'
            },
            {
                'template': 'ruuvi-webhook.service.j2',
                'output': '/etc/systemd/system/ruuvi-webhook.service',
                'mode': 0o644,
                'owner': 'root'
            }
        ]
        
        success = True
        for service in services:
            output_path = Path(service['output'])
            if self.generator.generate_file(service['template'], output_path):
                self.generator.set_file_permissions(
                    output_path, 
                    service['mode'], 
                    service['owner']
                )
            else:
                success = False
        
        return success
    
    def generate_configuration_files(self) -> bool:
        """Generate configuration files"""
        configs = [
            {
                'template': 'docker-compose.yml.j2',
                'output': 'docker-compose.yml',
                'mode': 0o644,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'env.j2',
                'output': '.env',
                'mode': 0o600,
                'owner': self.config.ruuvi_user
            },
            {
                'template': 'mosquitto.conf.j2',
                'output': 'config/mosquitto/mosquitto.conf',
                'mode': 0o644,
                'owner': self.config.ruuvi_user
            }
        ]
        
        success = True
        for config in configs:
            output_path = self.output_dir / config['output']
            if self.generator.generate_file(config['template'], output_path):
                self.generator.set_file_permissions(
                    output_path, 
                    config['mode'], 
                    config['owner']
                )
            else:
                success = False
        
        return success
    
    def generate_all(self) -> bool:
        """Generate all files"""
        tasks = [
            ("Python scripts", self.generate_python_scripts),
            ("Shell scripts", self.generate_shell_scripts),
            ("SystemD services", self.generate_systemd_services),
            ("Configuration files", self.generate_configuration_files)
        ]
        
        success = True
        for task_name, task_func in tasks:
            logging.info(f"Generating {task_name}...")
            if not task_func():
                logging.error(f"Failed to generate {task_name}")
                success = False
        
        return success

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Ruuvi Home Setup File Generator")
    parser.add_argument("config", help="Configuration file (YAML or JSON)")
    parser.add_argument("--type", choices=["python", "shell", "systemd", "config", "all"], 
                       default="all", help="Type of files to generate")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    config_file = Path(args.config)
    if not config_file.exists():
        logging.error(f"Configuration file not found: {config_file}")
        sys.exit(1)
    
    generator = RuuviSetupGenerator(config_file)
    
    # Generate requested files
    if args.type == "python":
        success = generator.generate_python_scripts()
    elif args.type == "shell":
        success = generator.generate_shell_scripts()
    elif args.type == "systemd":
        success = generator.generate_systemd_services()
    elif args.type == "config":
        success = generator.generate_configuration_files()
    else:
        success = generator.generate_all()
    
    if success:
        logging.info("File generation completed successfully")
        sys.exit(0)
    else:
        logging.error("File generation failed")
        sys.exit(1)

if __name__ == "__main__":
    main()